#! /bin/sh

# example usage
# unwarp_bupbdown_report.sh -t temp-unwarp_fieldmap -r report-unwarp_fieldmap [-n 6]

#---------variables---------#
tmpdir=temp-unwarp_bupbdown                 # name of directory for intermediate files
reportdir=report-unwarp_bupbdown 	    # report dir
logfile_name=unwarp_bupbdown_report.log     # Log file 
scriptdir=`dirname $0`



#----------- Utility Functions ----------#
usage_exit() {
      cat <<EOF

  Generates report for correction of B0 inhomogeneity distortion using blip-up, blip-down images

  Usage:   
  
    $CMD -t <directory with intermediade files from unwarp_bupbdown> -r <directory to put the generated reports> 

EOF
    exit 1;
}

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

while getopts t:r:s:o:n: OPT
 do
 case "$OPT" in 
   "t" ) tmpdir="$OPTARG";; 
   "r" ) reportdir="$OPTARG";;
   "o" ) outdir="$OPTARG";;
    * )  usage_exit;;
 esac
done;

#------------- Setting things up  --------------------#

LF=$reportdir/$logfile_name
RF=$reportdir/unwarp_bupbdown_report

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

echo "---" > ${RF}.Rmd
echo "title: QA report for correction of inhomogeneous magnetic suceptibility-induced distortions using a pair of blip-up, blip-down images " >> ${RF}.Rmd
echo "output:" >> ${RF}.Rmd
echo "  html_document:" >> ${RF}.Rmd
echo "    keep_md: yes" >> ${RF}.Rmd
echo "    toc: yes" >> ${RF}.Rmd 
echo "    force_captions: TRUE" >> ${RF}.Rmd 
echo "---" >> ${RF}.Rmd

# warped S0s gif
T $scriptdir/image_to_movie.sh $tmpdir/S0_images.nii.gz $reportdir/native_S0s.gif
echo "## Native, warped S0 image " >> ${RF}.Rmd 
echo "![](native_S0s.gif) \n" >> ${RF}.Rmd

# unwarped B0s gif
T $scriptdir/image_to_movie.sh $tmpdir/unwarped_S0_images.nii.gz $reportdir/unwarped_S0s.gif
echo "## Unwarped S0 image " >> ${RF}.Rmd 
echo "![](unwarped_S0s.gif) \n" >> ${RF}.Rmd

# TODO: show fieldmap


T R -e library\(rmarkdown\)\;rmarkdown::render\(\"${RF}.Rmd\"\)
