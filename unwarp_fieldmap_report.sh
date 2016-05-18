#! /bin/sh

# example usage
# unwarp_fieldmap_report.sh -t temp-unwarp_fieldmap -r report-unwarp_fieldmap -s .900

#---------variables---------#
tmpdir=temp-unwarp_fieldmap                 # name of directory for intermediate files
reportdir=unwarp_fieldmap_report 	    # report dir
logfile_name=unwarp_fieldmap_report.log     # Log file 
sl=.900                                     # signal loss threshold
scriptdir=`dirname $0`


#----------- Utility Functions ----------#
usage_exit() {
      cat <<EOF

  Generates report for correction of B0 inhomogeneity distortion

  Usage:   
  
    $CMD -t <directory with intermediade files from unwarp_fieldmap> -r <directory to put the generated reports>
  
    Option: 
    -s <signal loss threshold>

EOF
    exit 1;
}

#---------------- Utility Functions --------------#

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

while getopts t:r:s:o:m: OPT
 do
 case "$OPT" in 
   "t" ) tmpdir="$OPTARG";; 
   "r" ) reportdir="$OPTARG";;
   "s" ) SL="$OPTARG";;
   "o" ) outdir="$OPTARG";;
   "m" ) method="$OPTARG";;
    * )  usage_exit;;
 esac
done;


#------------- Setting things up  --------------------#

LF=$reportdir/$logfile_name
RF=$reportdir/unwarp_fieldmap_report

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

#------------- Begin Report  ----------------#

echo "---" > ${RF}.Rmd
echo "title: QA report for correction of magnetic suceptibility-induced distortions using an aquired fieldmap " >> ${RF}.Rmd
echo "output:"           >> ${RF}.Rmd
echo "  html_document: " >> ${RF}.Rmd
echo "    keep_md: yes " >> ${RF}.Rmd
echo "    toc: yes "     >> ${RF}.Rmd 
echo "    force_captions: TRUE " >> ${RF}.Rmd 
echo "---" >> ${RF}.Rmd

echo \# DTI UNWARP FIELDMAP REPORT >> ${RF}.Rmd


T fslstats $tmpdir/native_fmap_ph_filtered -R
T fslmaths $tmpdir/native_fmap_ph_filtered -mas $tmpdir/native_fmap_mag_brain_mask $tmpdir/native_fmap_brain
v=`fslstats $tmpdir/native_fmap_ph_filtered -R | awk '{print $1}'`
V=`fslstats $tmpdir/native_fmap_brain -P 5 -P 95`
T fslmaths $tmpdir/native_fmap_ph_filtered -sub $v -add 10 -mas $tmpdir/native_fmap_mag_brain_mask $reportdir/fmap_overlay
T fslstats $reportdir/fmap_overlay -P 5 -P 95
v=`fslstats $reportdir/fmap_overlay -P 5 -P 95`
T overlay 0 0 $tmpdir/native_fmap_mag -a $reportdir/fmap_overlay $v $reportdir/fmap_overlay
T $scriptdir/image_to_gif.sh $reportdir/fmap_overlay $reportdir/fmap+mag.gif

T /bin/cp ${FSLDIR}/etc/luts/ramp.gif $reportdir/ramp.gif
T /bin/cp ${FSLDIR}/etc/luts/ramp2.gif $reportdir/ramp2.gif

echo \#\# Fieldmap overlaid on magnitude image >> ${RF}.Rmd
#echo `echo $V | awk '{print $1}'` <IMG src=./ramp.gif width=106 height=14 border=0 align=middle> `echo $V | awk '{print $2}'` [rad/sec] >> ${RF}.Rmd
echo "![](fmap+mag.gif) \n"  >> ${RF}.Rmd

T fslstats $tmpdir/unwarp_shift -R -P 1 -P 99
O=`fslstats $tmpdir/unwarp_shift -R -P 1 -P 99`
p=`echo $O | awk '{print $3}'`
q=`echo $O | awk '{print $4}'`
p=`echo "scale=1; $p * -1" | bc`
T fslmaths $tmpdir/unwarp_shift -mul -1 $reportdir/shiftmap_overlay
T overlay 1 0 $tmpdir/coregistered_fmap_mag_brain -a $tmpdir/unwarp_shift 0 $q $reportdir/shiftmap_overlay 0 $p $reportdir/shiftmap_overlay
T $scriptdir/image_to_gif.sh $reportdir/shiftmap_overlay $reportdir/unwarp_shift+mag.gif

echo \#\# Unwarping shift map in voxels >> ${RF}.Rmd
echo "-$p <IMG src=./ramp2.gif width=106 height=14 border=0 align=middle> 0 <IMG src=./ramp.gif width=106 height=14 border=0 align= middle >$q (positive values indicate warps in the posterior direction)"  >>  ${RF}.Rmd
echo "![](unwarp_shift+mag.gif) \n"  >> ${RF}.Rmd

T flirt -in $tmpdir/rewarped_fmap_mag_brain_siglossed -ref $tmpdir/native_S0_brain -applyxfm -init $tmpdir/fieldmap_to_diffusion.mat -o $reportdir/rewarped_mag
T $scriptdir/image_to_gif.sh $reportdir/rewarped_mag $reportdir/coregistered_rewarped_fmap_mag_brain_siglossed.gif
T $scriptdir/image_to_gif.sh $tmpdir/native_S0 $reportdir/native_S0.gif
T whirlgif -o $reportdir/native_movie2.gif -loop -time 50 $reportdir/native_S0.gif $reportdir/coregistered_rewarped_fmap_mag_brain_siglossed.gif

echo \#\# Registration of brain images between original b=0 and rewarped magnitude image  >> ${RF}.Rmd
echo "![](native_movie2.gif) \n"  >> ${RF}.Rmd

T $scriptdir/image_to_gif.sh $tmpdir/unwarped_S0 $reportdir/unwarped_S0.gif
T $scriptdir/image_to_gif.sh $tmpdir/native_S0 $reportdir/native_S0.gif
T whirlgif -o $reportdir/S0_movie2.gif -loop -time 50 $reportdir/unwarped_S0.gif $reportdir/native_S0.gif

echo \#\# Uncorrected and corrected b=0 images  >> ${RF}.Rmd
echo "![](S0_movie2.gif) \n"  >> ${RF}.Rmd

T fslstats $tmpdir/coregistered_fmap_mag_brain.nii.gz -P 20 -P 90
v=`fslstats $tmpdir/coregistered_fmap_mag_brain.nii.gz -P 20 -P 90`
T $scriptdir/image_to_gif.sh $tmpdir/coregistered_fmap_mag $reportdir/coregistered_fmap_mag.gif -i $v
T whirlgif -o $reportdir/movie3.gif -loop -time 50  $reportdir/unwarped_S0.gif $reportdir/coregistered_fmap_mag.gif 

echo \#\# Corrected b=0 images and the fieldmap magnitude image >> ${RF}.Rmd
echo "![](movie3.gif) \n"  >> ${RF}.Rmd

T overlay 1 0 $tmpdir/unwarped_S0 -a $tmpdir/coregistered_fmap_sigloss $sl 1 $reportdir/sigloss_overlay
T $scriptdir/image_to_gif.sh $reportdir/sigloss_overlay $reportdir/S0+sigloss.gif

echo \#\# Corrected b0 image and signal loss estimated from fieldmap  >> ${RF}.Rmd
echo "![](S0+sigloss.gif) \n"  >> ${RF}.Rmd


T R -e library\(rmarkdown\)\;rmarkdown::render\(\"${RF}.Rmd\"\)
