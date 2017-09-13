#!/usr/bin/env bash
set -x
# Script to run pc_align on HiRISE point cloud using a less dense (i.e. CTX or HRSC) DEM or ASP point cloud as reference

# Summary:
# This script runs pc_align and then creates DEM at 1 m/px and a pair of orthoimages at 2 resolutions at 1 m/px and 0.25 m/px
# Also creates hillshade for the DEM
# Dependencies:
#      NASA Ames Stereo Pipeline
#      USGS ISIS3
#      GDAL

# Just a simple function to print a usage message
print_usage (){
    echo ""
    echo "Usage: asp_hirise_pc_align2dem.sh -d <stereodirs.lis> -m <max-displacement> -r <reference-dem>"
    echo " Where <stereodirs.lis> is a file containing the name of the subdirectories to loop over, 1 per line"
    echo " <max-displacement> is the maximum displacement to pass to pc_align (type pc_align --help for details)"
    echo " and <reference-dem> is the DEM, including path, to align the HiRISE point cloud to."
    echo "  Subdirectories containing stereopairs must all exist within the same root directory"
    echo "  Furthermore, the names listed in <stereodirs.lis> will be used as the file prefix for output generated by this script"
}

### Check for sane commandline arguments

if [[ $# = 0 ]] || [[ "$1" != "-"* ]] ; then
    # print usage message and exit
    print_usage
    exit
elif  [[ "$1" = "-"* ]]; then  # Else use getopts to parse flags that may have been set
    while getopts ":d:m:r:" opt; do
        case $opt in
          d)
              if [ ! -e "$OPTARG" ]; then
                  echo "ERROR: File $OPTARG not found" #>&2
                  # print usage message and exit
                  print_usage
                  exit 1
              fi
              dirs=$OPTARG
              ;;
          m)
              # Test that the argument accompanying the m option is a positive integer
              if ! test "$OPTARG" -gt 0 2> /dev/null ; then
                  echo "ERROR: $OPTARG not a valid argument" #>&2
                  echo "The maximum displacement must be a positive integer" #>&2
                  # print usage message and exit
                  print_usage
                  exit 1
              fi
              maxd=$OPTARG
              ;;
          r)
              if [ ! -e "$OPTARG" ]; then
                  echo "ERROR: File $OPTARG not found" #>&2
                  # print usage message and exit
                  print_usage
                  exit 1
              fi
              refdem=$OPTARG
              ;;
          \?)
              # Error to stop the script if an invalid option is passed
              echo "Invalid option: -$OPTARG" #>&2
              # print usage message and exit
              print_usage
              exit 1
              ;;
          :)
              # Error to prevent script from continuing if flag is not followed by at least 1 argument
              echo "ERROR: Option -$OPTARG requires an argument." #>&2
              # print usage message and exit
              print_usage
              exit 1
              ;;
        esac
    done
fi

# If we've made it this far, commandline args look sane and specified file exists
# load GDAL module for Uchicago SLURM nodes if we are on a SLURM cluster
if hash module 2>/dev/null; then
    module load gdal/1.11
fi

## Release the Kracken!
echo "Start asp_hirise_pc_align2dem $(date)"
# loop through the directories listed in "stereodirs.lis" and run through point2dem process
for i in $( cat ${dirs} ); do
    echo "Working on $i"
    cd $i || exit 1

    # extract the proj4 string from one of the map-projected image cubes and store it in a variable (we'll need it later for point2dem)
    proj=$(awk '{print("gdalsrsinfo -o proj4 "$1"_RED.map.cub")}' stereopair.lis | sh | sed 's/'\''//g')
    echo "\t PROJ4 STRING: ${proj}"

    cd ./results || exit 1

    # Run pc_align on the HiRISE point cloud using the specified CTX point cloud as the reference.
    # Note that the HiRISE point cloud is listed before the CTX point cloud because pc_align runs faster on point clouds when the denser source is listed first
    pc_align --max-displacement $maxd --threads 16 $i-PC.tif $refdem --save-inv-transform --datum D_MARS -o dem_align/${i}_align
    if [ $? -ne 0 ]
    then
        echo "Failure running pc_align of HiRISE to $refdem at $(date)"
        exit 1
    else
        echo "Success running pc_align of HiRISE to $refdem at $(date)"
    fi

    cd ./dem_align || exit 1
    mkdir -p logs

    echo "First  point2dem run at 1m/p"
    point2dem --threads 16 --t_srs "${proj}" -r mars --nodata -32767 -s 1 ${i}_align-trans_reference.tif --orthoimage -n --errorimage ../$i-L.tif -o ${i}_align_1
    if [ $? -ne 0 ]
    then
        echo "Failure running point2dem at 1m/p for $i at $(date)"
        exit 1
    else
        echo "Success running point2dem at 1m/p for $i at $(date)"
    fi

    #cleanup
    mv *-log-* ./logs/

    # Convert datum elevations to areoid elevations (this makes the elevations directly comparable to MOLA terrain products)
    # Create hillshade for 1 m/px DEM
    echo "Generating hillshade with gdaldem"
    dem_geoid ${i}_align_1-DEM.tif -o ${i}_align_1-DEM && gdaldem hillshade ${i}_align_1-DEM.tif ${i}_align_1-hillshade.tif
    if [ $? -ne 0 ]
    then
        echo "Failure running dem_geoid for $i at $(date)"
        exit 1
    else
        echo "Success running dem_geoid for $i at $(date)"
    fi

    #cleanup
    mv *-log-* ./logs/

    # Run point2dem again at full resolution TODO: maybe make this optional or give options like 0.75, 0.50, 0.25
    echo "Second point2dem run at 0.25m/p"
    point2dem --threads 16 --t_srs "${proj}" -r mars --nodata -32767 -s 0.25 ${i}_align-trans_reference.tif --orthoimage ../$i-L.tif -o ${i}_align_025 --no-dem
    if [ $? -ne 0 ]
    then
        echo "Failure running point2dem at 0.25m/p for $i at $(date)"
        exit 1
    else
        echo "Success running point2dem at 0.25m/p for $i at $(date)"
    fi

    #cleanup
    mv *-log-* ./logs/

    cd ../../ || exit 1
done
echo "End   asp_hirise_pc_align2dem $(date)"
set -x
