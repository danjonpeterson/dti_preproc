#! /bin/sh

usage_exit() {
      cat <<EOF

  Generates report for the tensor fitting procedure 

  Usage:   
  
    $CMD -t <directory with intermediate files from unwarp_fieldmap> -r <directory to put the generated reports> -o <output directory> -k <input 4D dti file> -m <method used> -n <number of b0 volumes>
  

EOF
    exit 1;
}

#---------variables and defaults---------#
tmpdir=temp-fit_tensor                 # name of directory for intermediate files
reportdir=fit_tensor_report            # report dir
logfile_name=fit_tensor_report.log     # Log file 
method=restore
outdir=.
dti=DTI_64.nii.gz
scriptdir=`dirname $0`
s0_count=2


#----------- Utility Functions ----------#

T () {

 E=0 
 if [ "$1" = "-e" ] ; then  # just outputting and logging a message with T -e 
  E=1; shift  
 fi
 
 cmd="$*"
 echo $* | tee -a $LF       # read the command into the console, and the log file

 if [ "$E" != "1" ] ; then 
  $cmd 2>&1 | tee -a $LF    # run the command. read the output into a the log file. Stderr is not directed to the logfile
 fi

 echo  | tee -a $LF         # write an empty line to the console and log file
}

error_exit (){      
    echo "$1" >&2      # Send message to stderr
    echo "$1" >> $LF   # send message to log file
    exit "${2:-1}"     # Return a code specified by $2 or 1 by default.
}

#------------- Parse Parameters  --------------------#

while getopts t:r:s:o:k:m:n: OPT
 do
 case "$OPT" in 
   "t" ) tmpdir="$OPTARG";; 
   "r" ) reportdir="$OPTARG";;
   "o" ) outdir="$OPTARG";;
   "k" ) dti="$OPTARG";;
   "m" ) method="$OPTARG";;
   "n" ) s0_count="$OPTARG";;
    * )  usage_exit;;
 esac
done;

#------------- Setting things up  --------------------#

LF=$reportdir/$logfile_name
RF=$reportdir/fit_tensor_report

if [ -e $reportdir ]; then /bin/rm -Rf $reportdir;fi
mkdir -p $reportdir

#------------- Check dependencies ----------------#

command -v fsl > /dev/null 2>&1 || { error_exit "ERROR: FSL required for report, but not found (http://fsl.fmrib.ox.ac.uk/fsl). Aborting."; } 
command -v whirlgif > /dev/null 2>&1 || { error_exit "ERROR: whirlgif required for report, but not found. Aborting."; } 
command -v pandoc > /dev/null 2>&1 || { error_exit "ERROR: pandoc required for report, but not found (http://pandoc.org/). Aborting."; } 
command -v R > /dev/null 2>&1 || { error_exit "ERROR: R required for report, but not found (https://www.r-project.org). Aborting."; } 

rmarkdown_test=`R -q -e "\"rmarkdown\" %in% rownames(installed.packages())" | grep 1`
if [ "$rmarkdown_test" != "[1] TRUE" ]; then error_exit "ERROR: R package 'rmarkdown' required for report, but not found. 
Try running this command in R: 
install.packages(\"rmarkdown\") " ;fi


#------------- Begin report  --------------------#

echo "---"> ${RF}.Rmd
echo "title: QA report for tensor fitting as part of DTI preprocessing ">> ${RF}.Rmd
echo "output:"           >> ${RF}.Rmd
echo "  html_document: " >> ${RF}.Rmd
echo "    keep_md: yes " >> ${RF}.Rmd
echo "    toc: yes "     >> ${RF}.Rmd 
echo "    force_captions: TRUE " >> ${RF}.Rmd 
echo "---">> ${RF}.Rmd

echo \# FIT TENSOR REPORT  >> ${RF}.Rmd
echo "__tensor fitting method: $method __\n" >> ${RF}.Rmd


## FA
echo "## FA Image "   >> ${RF}.Rmd
T $scriptdir/image_to_gif.sh $outdir/dti_FA.nii.gz $reportdir/fa.gif
echo "![](fa.gif) \n" >> ${RF}.Rmd

## MD
echo "## MD Image"   >> ${RF}.Rmd
T $scriptdir/image_to_gif.sh $outdir/dti_MD.nii.gz $reportdir/md.gif
echo "![](md.gif) \n" >> ${RF}.Rmd

if [ "$method" = "restore" ]; then

 ## Outlier count
 T fslhd $dti | grep ^dim1 | awk '{print $2}'
 T fslhd $dti | grep ^dim2 | awk '{print $2}'
 T fslhd $dti | grep ^dim3 | awk '{print $2}'
 xdim=`fslhd $dti | grep ^dim1 | awk '{print $2}'`
 ydim=`fslhd $dti | grep ^dim2 | awk '{print $2}'`
 zdim=`fslhd $dti | grep ^dim3 | awk '{print $2}'`
 echo "##Outliers across volumes"   >> ${RF}.Rmd
 T fslmaths $tmpdir/dti_outlier_map.nii.gz -Xmean -Ymean -Zmean -mul $xdim -mul $ydim -mul $zdim $reportdir/outlier_ts_avg
 T tsplot $reportdir/tsplot_temp -f $reportdir/outlier_ts_avg.nii.gz -C 0 0 0 $reportdir/outliers_ts.txt
 
 cat $reportdir/outliers_ts.txt | tail -n +`echo $s0_count+1|bc` > $reportdir/outliers_ts_trim.txt
 T fsl_tsplot -i $reportdir/outliers_ts_trim.txt -o $reportdir/outlier_plot.png -t Outliers -x Volume
 echo "![](outlier_plot.png) \n" >> ${RF}.Rmd
 
 ## outlier count across volumes
 echo "## Outlier Image "   >> ${RF}.Rmd
 T $scriptdir/image_to_gif.sh $tmpdir/dti_outlier_count.nii.gz $reportdir/outlier_count.gif
 echo "![](outlier_count.gif) \n" >> ${RF}.Rmd
 
 ## Sigma
 sigma=`fslstats $tmpdir/sigma_map -P 50`
 echo "__Median noise level across the image: $sigma __ \n"   >> ${RF}.Rmd
 
 # log S0
 echo "## log - S0 Image "   >> ${RF}.Rmd
 T fslmaths $tmpdir/dti_log_s0.nii.gz -mas $tmpdir/dti_MD.nii.gz $tmpdir/dti_log_s0_mas.nii.gz
 T $scriptdir/image_to_gif.sh $tmpdir/dti_log_s0_mas.nii.gz $reportdir/S0.gif
 echo "![](S0.gif) \n" >> ${RF}.Rmd
 
 ## noise map
 #echo "<B>Noise Image </B><BR>"   >> ${RF}.Rmd
 #image_to_gif $tmpdir/noise_map.nii.gz $reportdir/noise.gif
 #echo "<IMG src="./noise.gif" width="1200" height="100" border="0"><BR><BR>" >> ${RF}.Rmd

fi

if [ "$method" = "fsl" ]; then
 # S0
 echo "## S0 Image "   >> ${RF}.Rmd
 T $scriptdir/image_to_gif.sh $tmpdir/dti_S0.nii.gz $reportdir/S0.gif
 echo "![](S0.gif) \n" >> ${RF}.Rmd
 
 #SSE 
 echo "## Sum-squared error Image "   >> ${RF}.Rmd
 T $scriptdir/image_to_gif.sh $tmpdir/dti_sse.nii.gz $reportdir/SSE.gif
 echo "![](SSE.gif) \n" >> ${RF}.Rmd

fi

T R -e library\(rmarkdown\)\;rmarkdown::render\(\"${RF}.Rmd\"\)
