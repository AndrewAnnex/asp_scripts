#!/bin/bash

# Summary:
# Script to take Level 1eo CTX stereopairs, run them through NASA Ames stereo Pipeline.
# The script uses ASP's bundle_adjust tool to perform bundle adjustment on each stereopair separately.
# The script also runs ASP's cam2map4stereo.py on the input cubes, but the resulting map-projected cubes are only used as a convenient source of ideal projection information;
#  they're not actually used for stereo matching.  (This is a legacy of a much earlier version of the code and now is merely a lazy workaround for generating sensible map projection
#  information that is used later. This should really be done with a few calls to ISIS3's `camrange`. )
# This script is capable of processing many stereopairs in a single run and uses GNU parallel
#  to improve the efficiency of the processing and reduce total wall time.  


# Dependencies:
#      NASA Ames Stereo Pipeline
#      USGS ISIS3
#      GDAL
#      GNU parallel
# Optional dependency:
#      Dan's GDAL Scripts https://github.com/gina-alaska/dans-gdal-scripts
#        (used to generate footprint shapefile based on initial DEM)


# Just a simple function to print a usage message
print_usage (){
echo ""
echo "Usage: $(basename $0) -s <stereo.default> -p <productIDs.lis>"
echo " Where <productIDs.lis> is a file containing a list of the IDs of the CTX products to be processed."
echo " Product IDs belonging to a stereopair must be listed sequentially."
echo " The script will search for CTX Level 1eo products in the current directory before processing with ASP."
echo " "
echo "<stereo.default> is the name and absolute path to the stereo.default file to be used by the stereo command."
}

### Check for sane commandline arguments

if [[ $# = 0 ]] || [[ "$1" != "-"* ]]; then
# print usage message and exit
print_usage
exit 0

   # Else use getopts to parse flags that may have been set
elif  [[ "$1" = "-"* ]]; then
    while getopts ":p:s:" opt; do
	case $opt in
	    p)
		prods=$OPTARG
		if [ ! -e "$OPTARG" ]; then
        	    echo "$OPTARG not found" >&2
                    # print usage message and exit
                    print_usage
        	    exit 1
                fi

		;;
	    s)
		config=$OPTARG
		if [ ! -e "$OPTARG" ]; then
        	    echo "$OPTARG not found" >&2
                    # print usage message and exit
                    print_usage
        	    exit 1
                fi
                # Export $config so that GNU parallel can use it later
                export config=$OPTARG
		;;
	   \?)
                # Error to stop the script if an invalid option is passed
                echo "Invalid option: -$OPTARG" >&2
                exit 1
                ;;
            :)
                # Error to prevent script from continuing if flag is not followed by at least 1 argument
                echo "Option -$OPTARG requires an argument." >&2
                exit 1
                ;;
        esac
   done
fi 

# If we've made it this far, commandline args look sane and specified files exist

    # Check that ISIS has been initialized by looking for pds2isis,
    #  if not, initialize it
    if [[ $(which pds2isis) = "" ]]; then
        echo "Initializing ISIS3"
        source $ISISROOT/scripts/isis3Startup.sh
    # Quick test to make sure that initialization worked
    # If not, print an error and exit
       if [[ $(which pds2isis) = "" ]]; then
           echo "ERROR: Failed to initialize ISIS3" 1>&2
           exit 1
       fi
    fi

######

    date


#######################################################
## Housekeeping and Creating Some Support Files for ASP
#######################################################
# Create a 3-column, space-delimited file containing list of CTX stereo product IDs and the name of the corresponding directory that will be created for each pair
# For the sake of concision, we remove the the 2 character command mode indicator and the 1x1 degree region indicator from the directory name
awk '{printf "%s ", $0}!(NR % 2){printf "\n"}' $prods | sed 's/ /_/g' | awk -F_ '{print($1"_"$2"_"$3"_"$4"_"$5" "$6"_"$7"_"$8"_"$9"_"$10" "$1"_"$2"_"$3"_"$6"_"$7"_"$8)}' > stereopairs.lis

# Extract Column 3 (the soon-to-be- directory names) from stereopairs.lis and write it to a file called stereodirs.lis
# This file will be specified as an input argument for asp_ctx_map2dem.sh or asp_ctx_para_map2dem.sh
awk '{print($3)}' stereopairs.lis > stereodirs.lis

# Make directories named according to the lines in stereodirs.lis
mkdir $(cat stereodirs.lis )

# Now extract each line from stereopairs.lis (created above) and write it to a textfile inside the corresponding subdirectory we created on the previous line
# These files are used to ensure that the input images are specified in the same order during every step of `stereo` in ASP
awk '{print $1" "$2 >$3"/stereopair.lis"}' stereopairs.lis

####################################################################################
# Bundle adjust *all* of the input products
# You must modify the hard-coded bundle adjustment prefix inside the FOR loop below if you want to bundle adjust all of the input products together
# rather than running bundle_adjust separately on each stereopair.
# The practical difference between these two approaches is non-trivial. Consider yourself warned
#awk '{print($1".lev1eo.cub")}' $prods | tr '\n' ' ' | tr -s ' ' | awk '{print("bundle_adjust "$0" -o ba_results/ba")}' | sh
###################################################################################

# TODO: Test that the Level1eo cubes exist before trying to move them, throw error and exit if they don't exist
#prodarr=($(awk '{print $1".lev1eo.cub"}' ${prods} ))

# for (( <EXPR1> ; <EXPR2> ; <EXPR3> )); do
#   <LIST>
# done
# ((n_elements=${#prodarr[@]}, max_index=n_elements - 2))
# for (( j=0 ; j <= max_index ; j+=2 )); do
#     if [ -e ${prodarr[$j]}.lev1eo.cub ] && [ -e ${prodarr[$j+1]}.lev1eo.cub  ]; then
	
#     else
	
#     fi

# done



# Move the Level 1eo cubes into the directory named for the stereopair they belong to
awk '{print("mv "$1".lev1eo.cub "$3)}' stereopairs.lis | sh
awk '{print("mv "$2".lev1eo.cub "$3)}' stereopairs.lis | sh

# If this script is run as part of a job on a computing cluster using SLURM, we write the nodelist to a file named "nodelist.lis" so parallel_stereo can use it
# This line is NOT portable to environments that are NOT running SLURM
scontrol show hostname $SLURM_NODELIST | tr ' ' '\n' > nodelist.lis
#######################################################

    
######
## Use GNU parallel to run many instances of cam2map4stereo.py at once and project the images of each stereopair into a common projection
# Define a function that GNU parallel will call to run cam2map4stereo.py
function cam2map4stereo() {
    cd $3 
cam2map4stereo.py $1.lev1eo.cub $2.lev1eo.cub
}
# export the function so GNU parallel can use it
export -f cam2map4stereo
# Run the function using parallel
parallel --colsep ' ' --joblog parallel_cam2map4stereo.log cam2map4stereo :::: stereopairs.lis 


##  Run ALL stereo in series for each stereopair using `parallel_stereo`
# This is not the most resource efficient way of doing this but it's a hell of a lot more efficient compared to using plain `stereo` in series
for i in $( cat stereodirs.lis ); do
    
    cd $i
    # Store the names of the Level1 EO cubes in variables
    L=$(awk '{print($1".lev1eo.cub")}' stereopair.lis)
    R=$(awk '{print($2".lev1eo.cub")}' stereopair.lis)

    # Run ASP's bundle_adjust on the given stereopair
    echo "Begin bundle_adjust on "$i" at "$(date)
    bundle_adjust $L $R -o adjust/ba
    echo "Finished bundle_adjust on "$i" at "$(date)
    
    # Note that we specify ../nodelist.lis as the file containing the list of hostnames for `parallel_stereo` to use
    # You may wish to edit out the --nodes-list argument if running this script in a non-SLURM environment
    # See the ASP manual for information on running `parallel_stereo` with a node list argument that is suitable for your environment

    # We break parallel_stereo into 3 stages in order to optimize resource utilization. The first and third stages let parallel_stereo decide how to do this.
    # For the second stage, we specify an optimal number of processes and number of threads to use for multi-process and single-process portions of the code.
    # By default, we assume running on a machine with 16 cores. Users should tune this to suit their hardware.

    echo "Begin parallel_stereo on "$i" at "$(date)
    
    # stop parallel_stereo after correlation
    parallel_stereo --nodes-list=../nodelist.lis --stop-point 2 $L $R -s ${config} results_ba/${i}_ba --bundle-adjust-prefix adjust/ba

    # attempt to optimize parallel_stereo for running on 16-core machines for Steps 2 (refinement) and 3 (filtering)
    # Users should customize the number of processors, threads for multiprocessing and threads for single processing to values that suit their hardware
    parallel_stereo --nodes-list=../nodelist.lis --processes 2 --threads-multiprocess 8 --threads-singleprocess 16 --entry-point 2 --stop-point 4 $L $R -s ${config} results_ba/${i}_ba --bundle-adjust-prefix adjust/ba

    # finish parallel_stereo using default options for Stage 4 (Triangulation)
    parallel_stereo --nodes-list=../nodelist.lis --entry-point 4 $L $R -s ${config} results_ba/${i}_ba --bundle-adjust-prefix adjust/ba
    
    cd ../
    echo "Finished parallel_stereo on "$i" at "$(date)
done


# # loop through the directories listed in stereodirs.lis and run point2dem, image footprint and hillshade generation
# for i in $( cat stereodirs.lis ); do
#     # cd into the directory containing the stereopair i
#     cd $i
    
#     # extract the proj4 string from one of the map-projected image cubes and store it in a variable (we'll need it later for point2dem)
#     proj=$(awk '{print("gdalsrsinfo -o proj4 "$1".map.cub")}' stereopair.lis | sh | sed 's/'\''//g')
    
#     # cd into the results directory for stereopair $i
#     cd results_ba/	       
#     # run point2dem with orthoimage and intersection error image outputs. no hole filling
#     echo point2dem --threads 16 --t_srs \"${proj}\" -r mars --nodata -32767 -s 18 -n --errorimage ${i}_ba-PC.tif --orthoimage ${i}_ba-L.tif -o dem/${i}_ba | sh

#     # Generate hillshade (useful for getting feel for textural quality of the DEM)
#     gdaldem hillshade ./dem/${i}_ba-DEM.tif ./dem/${i}_ba-hillshade.tif
    
#     ## OPTIONAL ##
#     # # Create a shapefile containing the footprint of the valid data area of the DEM 
#     # # This requires the `gdal_trace_outline` tool from the "Dan's GDAL Scripts" collection
#     # # If you don't have this tool installed and don't comment out the next line, the script will throw an error but will continue to execute
#     # gdal_trace_outline dem/${i}_ba-DEM.tif -ndv -32767 -erosion -out-cs en -ogr-out dem/${i}_ba_footprint.shp
    

#     cd ../../
# done

date
