#!/bin/bash

# Summary:
# This script runs pc_align using a CSV of MOLA shots as a reference and then creates DEMs at 24 m/px and orthoimages at 24 m/px and 6 m/px

# Input: text file containing list of the root directories for each stereopair
# Output will be sent to <stereopair root dir>/results/dem_align


# Dependencies:
#      NASA Ames Stereo Pipeline
#      USGS ISIS3
#      GDAL


# Just a simple function to print a usage message
print_usage (){
echo ""
echo "Usage: $(basename $0) -d <stereodirs.lis> -m <max-displacement>"
echo " Where <stereodirs.lis> is a file containing the name of the subdirectories to loop over, 1 per line"
echo " and <max-displacement> is the maximum displacement to pass to pc_align (type pc_align --help for details)"
echo "  Subdirectories containing stereopairs must all exist within the same root directory"
echo "  Furthermore, the names listed in <stereodirs.lis> will be used as the file prefix for output generated by this script"
}

### Check for sane commandline arguments

if [[ $# = 0 ]] || [[ "$1" != "-"* ]] ; then
# print usage message and exit
print_usage
exit

   # Else use getopts to parse flags that may have been set
elif  [[ "$1" = "-"* ]]; then
    while getopts ":d:m:" opt; do
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
                  else
		    maxd=$OPTARG
		 fi
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

## Release the Kracken!

date
# loop through the directories listed in "stereodirs.lis" and run through point2dem process
for i in $( cat ${dirs} ); do
    echo Working on $i
    cd $i
    # extract the proj4 string from one of the map-projected image cubes and store it in a variable (we'll need it later for point2dem)
    proj=$(awk '{print("gdalsrsinfo -o proj4 "$1".map.cub")}' stereopair.lis | sh | sed 's/'\''//g')
    
    # Move down into the results directory for stereopair $i
    cd ./results_map_ba
    # run pc_align and send the output to a new subdirectory called dem_align
    echo "Running pc_align..."
    pc_align --num-iterations 2000 --threads 16 --max-displacement $maxd --highest-accuracy ${i}_map_ba-PC.tif ../${i}_pedr4align.csv -o dem_align/${i}_map_ba_align --datum D_MARS --save-inv-trans
    
    # move down into the directory with the pc_align output, which should be called "dem_align"
    cd ./dem_align
    # Create 24 m/px DEM, ortho, normalized DEM, errorimage, no hole filling
    echo point2dem --threads 16 --t_srs \"${proj}\" -r mars --nodata -32767 -s 24 ${i}_map_ba_align-trans_reference.tif --orthoimage -n --errorimage ../${i}_map_ba-L.tif -o ${i}_map_ba_align_24 | sh
    
    # Run dem_geoid on the align'd 24 m/px DEM so that the elevation values are comparable to MOLA products
    echo dem_geoid --threads 16 ${i}_map_ba_align_24-DEM.tif -o ${i}_map_ba_align_24-DEM | sh
    
    # Create hillshade for 24 m/px DEM
    echo "Generating hillshade with gdaldem"
    gdaldem hillshade ${i}_map_ba_align_24-DEM.tif ${i}_map_ba_align_24-hillshade.tif
    
    # Create 6 m/px ortho, no hole-filling, no DEM
    echo point2dem --threads 16 --t_srs \"${proj}\" -r mars --nodata -32767 -s 6 ${i}_map_ba_align-trans_reference.tif --orthoimage ../${i}_map_ba-L.tif -o ${i}_map_ba_align_6 --no-dem | sh
    
    echo "Done with ${i}_ba"
    # Move back up to the root of the stereo project   
    cd ../../../
done
echo "All done."
date
