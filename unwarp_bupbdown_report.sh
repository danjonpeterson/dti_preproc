#! /bin/sh

# example usage
# unwarp_bupbdown_report.sh -t temp-unwarp_fieldmap -r report-unwarp_fieldmap 

#---------variables---------#
tmpdir=temp-unwarp_bupbdown                 # name of directory for intermediate files
reportdir=report-unwarp_bupbdown 	    # report dir
logfile_name=unwarp_bupbdown_report.log     # Log file 


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

#------------- Parse Parameters  --------------------#

while getopts t:r:s:o: OPT
 do
 case "$OPT" in 
   "t" ) tmpdir="$OPTARG";; 
   "r" ) reportdir="$OPTARG";;
   "o" ) outdir="$OPTARG";;
    * )  usage_exit;;
 esac
done;

#------------- Begin report  --------------------#

LF=$reportdir/$logfile_name
RF=$reportdir/unwarp_bupbdown_report

SCRIPTDIR=`dirname $0`

if [ -e $reportdir ]; then /bin/rm -Rf $reportdir;fi
mkdir -p $reportdir

echo "---" > ${RF}.Rmd
echo "title: QA report for correction of inhomogeneous magnetic suceptibility-induced distortions using a pair of blip-up, blip-down images " >> ${RF}.Rmd
echo "output:" >> ${RF}.Rmd
echo "  html_document:" >> ${RF}.Rmd
echo "    keep_md: yes" >> ${RF}.Rmd
echo "    toc: yes" >> ${RF}.Rmd 
echo "    force_captions: TRUE" >> ${RF}.Rmd 
echo "---" >> ${RF}.Rmd

# warped S0s gif
T fslsplit $tmpdir/S0_images.nii.gz $reportdir/S0_images_ -t
T $SCRIPTDIR/image_to_gif.sh $reportdir/S0_images_0000.nii.gz $reportdir/S0_1.gif
T $SCRIPTDIR/image_to_gif.sh $reportdir/S0_images_0001.nii.gz $reportdir/S0_2.gif
T whirlgif -o $reportdir/native_S0s.gif -loop -time 50 $reportdir/S0_1.gif $reportdir/S0_2.gif
echo "## Native, warped S0 image " >> ${RF}.Rmd 
echo "![](native_S0s.gif) \n" >> ${RF}.Rmd

# unwarped B0s gif
T fslsplit $tmpdir/unwarped_S0_images.nii.gz $reportdir/unwarped_S0_images_ -t
T $SCRIPTDIR/image_to_gif.sh $reportdir/unwarped_S0_images_0000.nii.gz $reportdir/uw_S0_1.gif
T $SCRIPTDIR/image_to_gif.sh $reportdir/unwarped_S0_images_0001.nii.gz $reportdir/uw_S0_2.gif
T whirlgif -o $reportdir/unwarped_S0s.gif -loop -time 50 $reportdir/uw_S0_1.gif $reportdir/uw_S0_2.gif
echo "## Unwarped S0 image " >> ${RF}.Rmd 
echo "![](unwarped_S0s.gif) \n" >> ${RF}.Rmd

# TODO: show fieldmap


T R -e library\(rmarkdown\)\;rmarkdown::render\(\"${RF}.Rmd\"\)
