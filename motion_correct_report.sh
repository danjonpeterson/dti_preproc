#! /bin/sh

#example usage
#motion_correct_report.sh -t temp-motion_correct -r report-motion_correct -o dti_v2 -k DTI_64.nii.gz 

#---------variables---------#
tmpdir=temp-motion_correct                 # name of directory for intermediate files
method=not_entered
reportdir=motion_correct_report	           # report dir
logfile_name=motion_correct_report.log    # Log file 
outdir=.
dti=DTI_64.nii.gz
scale_and_skew=n
scriptdir=`dirname $0`


#----------- Utility Functions ----------#
usage_exit() {
      cat <<EOF

  Generates report for motion and eddy current correction 

  Usage:   
  
    $CMD -t <directory with intermediade files from unwarp_fieldmap> -r <directory to put the generated reports> -o <output directory> -k <input 4D dti file> -m method -i <index file if using topup>


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

threecolumnmeansd () {
    mean=`cat $1 | awk 'BEGIN {x=0;y=0;z=0;N=0};{x=x+$1;y=y+$2;z=z+$3;N=N+1}END {printf("%f, %f, %f",x/N,y/N,z/N)}'`
    xm=`echo $mean | awk '{print $1}'`; ym=`echo $mean | awk '{print $2}'`; zm=`echo $mean | awk '{print $3}'`
    sd=`cat $1 | awk 'BEGIN {x=0;y=0;z=0;N=0};{x=x+($1-"$xm")^2;y=y+($2-"$ym")^2;z=z+($3-"$zm")^2;N=N+1}END {printf("%f, %f, %f",sqrt(x/N),sqrt(y/N),sqrt(z/N))}'`
    echo $mean $sd
}

#------------- Parse Parameters  --------------------#

while getopts t:r:s:o:k:m:i: OPT
 do
 case "$OPT" in 
   "t" ) tmpdir="$OPTARG";; 
   "r" ) reportdir="$OPTARG";;
   "o" ) outdir="$OPTARG";;
   "k" ) dti="$OPTARG";;
   "m" ) method="$OPTARG";;
   "i" ) index="$OPTARG";;
    * )  usage_exit;;
 esac
done;

#------------- Setting things up  --------------------#

LF=$reportdir/$logfile_name
RF=$reportdir/motion_correct_report

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
echo "title: QA report for correction of subject motion and eddy-current induced distortions ">> ${RF}.Rmd
echo "output:"           >> ${RF}.Rmd
echo "  html_document: " >> ${RF}.Rmd
echo "    keep_md: yes " >> ${RF}.Rmd
echo "    toc: yes "     >> ${RF}.Rmd 
echo "    force_captions: TRUE " >> ${RF}.Rmd 
echo "---">> ${RF}.Rmd

echo \# MOTION CORRECTION REPORT  >> ${RF}.Rmd
echo "__motion correction method: $method __\n" >> ${RF}.Rmd


## framewise displacement 

dtidim4=`echo $tmpdir/dti_ecc.mat/* | wc -w`
echo "__number of volumes: $dtidim4 __\n" >> ${RF}.Rmd

i=2  #start at the second entry (b/c we are comparing this and the previous one)
while [ $i -lt `expr $dtidim4 + 1` ]; do ## loop through DWIs
 prev=`expr $i - 1`

 # when zero-indexed
 i_zi=`expr $i - 1`
 prev_zi=`expr $i - 2`
 
 i_zi_pad=`zeropad $i_zi 4`
 prev_zi_pad=`zeropad $prev_zi 4`
 
 # awk is not zero-indexed
 if [ "$method" = "eddy_with_topup" ]; then
  index_entry=`cat $index | awk -v n=$i '{print $n}'`
  prev_index_entry=`cat $index | awk -v n=$prev '{print $n}'`
 fi
  
 # skip seams in the index file
 if [ "$method" != "eddy_with_topup" ] || [ "$index_entry" = "$prev_index_entry" ]; then 
  # MC xform matrices ARE zero-indexed
#  T rmsdiff $tmpdir/dti_ecc.mat/MAT_$prev_zi_pad $tmpdir/dti_ecc.mat/MAT_$i_zi_pad $dti
  echo `rmsdiff $tmpdir/dti_ecc.mat/MAT_$prev_zi_pad $tmpdir/dti_ecc.mat/MAT_$i_zi_pad $dti` >> $reportdir/framewise_displacement.par
 else
  echo " Removing $prev -to- $i step from FWD calculation \n" >> ${RF}.Rmd
 fi

 i=`expr $i + 1`
done ## end while loop across DWIs

mean_fwd=`cat $reportdir/framewise_displacement.par | awk '{ sum += $1; n++ } END { if (n > 0) print sum / n; }'`

echo sd max median mean > $reportdir/fwd_summary.par
Rscript -e 'd<-scan("stdin", quiet=TRUE)' \
        -e 'cat(c(sd(d), max(d), median(d), mean(d), sep="\n"))' < $reportdir/framewise_displacement.par > $reportdir/fwd_summary.par

echo "## Relative Framewise Displacement"  >> ${RF}.Rmd
echo "__Mean: `cat $reportdir/fwd_summary.par | awk '{print $4}'` __ \n"  >> ${RF}.Rmd
echo "__Median: `cat $reportdir/fwd_summary.par | awk '{print $3}'` __ \n"  >>  ${RF}.Rmd
echo "__Max: `cat $reportdir/fwd_summary.par | awk '{print $2}'` __ \n"  >>  ${RF}.Rmd
echo "__Standard Deviation: `cat $reportdir/fwd_summary.par | awk '{print $1}'` __ \n"  >> ${RF}.Rmd


T fsl_tsplot -i $reportdir/framewise_displacement.par -o $reportdir/fwd.png -t "Framewise_Displacement" -y "[mm]" -x "Volume"

echo "![](fwd.png) \n" >>  ${RF}.Rmd


## generate rotation and translation plots
T fsl_tsplot -i $tmpdir/translation.par -o $reportdir/translation.png -t "Translation" -y [mm] -x Volume -a x,y,z
T fsl_tsplot -i $tmpdir/rotation.par -o $reportdir/rotation.png -t "Rotation" -y [degree] -x Volume -a x,y,z

echo "## Absolute Displacement" >> ${RF}.Rmd

meandisl=`cat $tmpdir/translation.par | awk 'BEGIN {x=0;N=0};{x=x+($1^2+$2^2+$3^2)^0.5;N=N+1}END {printf("%f",x/N)}'`
echo "__Mean displacement from t=0 : $meandisl [mm]__ \n" >> ${RF}.Rmd

meansdt=`threecolumnmeansd $tmpdir/translation.par`
meansdr=`threecolumnmeansd $tmpdir/rotation.par`
echo "__Mean translation: (x y z)=(`echo $meansdt | awk '{print $1,$2,$3}'`) [mm]__ \n" >> ${RF}.Rmd
echo "__Mean rotation: (x y z)=(`echo $meansdr | awk '{print $1,$2,$3}'`) [degrees]__ \n" >> ${RF}.Rmd
echo "![](translation.png) \n" >> ${RF}.Rmd
echo "![](rotation.png) \n" >> ${RF}.Rmd

echo "##Diffusion Volume Images" >> ${RF}.Rmd

T $scriptdir/image_to_movie.sh $dti $reportdir/uncorrected_movie.gif
echo "__Uncorrected diffusion volumes__ \n " >> ${RF}.Rmd
echo "![](uncorrected_movie.gif) \n" >> ${RF}.Rmd

if [ "$method" = "eddy_with_topup" ]; then
 T $scriptdir/image_to_movie.sh $tmpdir/dti_ecc.nii.gz $reportdir/corrected_movie.gif
else
 T $scriptdir/image_to_movie.sh $outdir/mc_`basename $dti` $reportdir/corrected_movie.gif
fi

echo "__Corrected diffusion volumes __\n " >> ${RF}.Rmd
echo "![](corrected_movie.gif) \n" >> ${RF}.Rmd

if [ "$scale_and_skew" = "y" ]; then
 echo "# Scale and skew "  >> ${RF}.Rmd
 T fsl_tsplot -i $tmpdir/scale.par -o $reportdir/scale.png -t "Scale"  -x Volume -a x,y,z
 T fsl_tsplot -i $tmpdir/skew.par -o $reportdir/skew.png -t "Skew" -x Volume -a x,y,z
 meansdS=`threecolumnmeansd $tmpdir/scale.par`
 meansds=`threecolumnmeansd $tmpdir/skew.par`
 echo Estimated distortion \n >> ${RF}.Rmd
 echo "Mean scale: (x y z)=(`echo $meansdS | awk '{print $1,$2,$3}'`) \n"  >> ${RF}.Rmd
 echo "Mean skew: \(x y z\)=\(`echo $meansds | awk '{print $1,$2,$3}'`) \n"  >> ${RF}.Rmd
 echo "![](scale.png) \n" >> ${RF}.Rmd
 echo "![](skew.png) \n" >> ${RF}.Rmd
fi

T R -e library\(rmarkdown\)\;rmarkdown::render\(\"${RF}.Rmd\"\)


