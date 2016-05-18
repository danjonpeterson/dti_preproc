#! /bin/sh

usage_exit() {
      cat <<EOF

  Correction for B0 inhomogeneity distortion using an acquired fieldmap

  Example Usage:   
   unwarp_fieldmap.sh -k raw_diffusion.nii.gz -f fieldmap_phase.nii.gz -m fieldmap_magnitude.nii.gz \\
                      -M brain_mask.nii.gz -t 0.567 -e 93.46
    
  
    -k <img>    : diffusion 4D data
    -f <img>    : fieldmap phase image (radian/sec)
    -m <img>    : fieldmap magnitude image
    -M <img>    : diffusion mask file
    -t <num>    : diffusion dwell time (ms - ex: 0.567) 
    -e <num>    : diffusion TE (ms - ex: 93.46)

    Option: 
    -p <img>    : fieldmap magnitude image mask file
    -s <num>    : percent signal loss threshold for B0 unwarping (default: 10)
    -n          : do not register between fieldmap and diffusion data
    -s          : no not generate HTML report
    -o          : output directory (defaut: current working directory)
    -r          : report directory
    -E          : don't run the commands, just echo them
    -F          : fast mode for testing (minimal iterations)

EOF
    exit 1;
}

#---------variables and defaults---------#
sl=10                               # default signal loss threshold
direction=y                         # distortion direction
tmpdir=temp-unwarp_fieldmap         # name of directory for intermediate files
LF=$tmpdir/unwarp_fieldmap.log      # default log filename
te="PARSE_ERROR"                    # field map TE (ex: 93.46)
esp="PARSE_ERROR"                   # field map echo spacing (ex: 0.576)
reg=y                               # coregister between fieldmap and DTI data
outdir=.                            # put output in PWD
generate_report=y                   # generate a report 
reportdir=$tmpdir/report            # directory for html report
mode=normal                         # run mode (normal,fast,echo)
scriptdir=`dirname $0`              # directory where dti_preproc scripts live
fast_testing=n                      # run with minimal processing for testing


#------------- Parse Parameters  --------------------#
[ "$4" = "" ] && usage_exit #show help message if fewer than four args

while getopts k:f:m:M:u:s:t:e:o:r:p:nsEF OPT
 do
 case "$OPT" in 
   "k" ) diffusion="$OPTARG";; 
   "f" ) dph="$OPTARG";;
   "m" ) mag="$OPTARG";;
   "M" ) mask="$OPTARG";;  
   "u" ) ud="$OPTARG";;
   "s" ) SL="$OPTARG";;
   "t" ) esp="$OPTARG";;  
   "e" ) te="$OPTARG";;
   "o" ) outdir="$OPTARG";;
   "n" ) reg=n;;
   "s" ) generate_report=0;;
   "r" ) reportdir="$OPTARG";;
   "p" ) mag_mask="$OPTARG";;
   "E" ) mode=echo;;
   "F" ) fast_testing=y;;
    * )  usage_exit;;
 esac
done;


#---------------- Utility Functions --------------#

T () {                      # main shell commands are run through here

 E=0 
 if [ "$1" = "-e" ] ; then  # just outputting and logging a message with T -e 
  E=1; shift  
 fi
 
 cmd="$*"
 echo $* | tee -a $LF       # echo the command into the console, and the log file

 if [ "$E" != "1" ] && [ "$mode" != "echo" ] ; then 
  $cmd 2>&1 | tee -a $LF    # run the command. redirect the output into the log file. Stderr is not directed to the logfile
 fi

 echo | tee -a $LF         # write an empty line to the console and log file
}

error_exit (){      
    echo "$1" >&2      # Send message to stderr
    echo "$1" >> $LF   # send message to log file
    exit "${2:-1}"     # Return a code specified by $2 or 1 by default.
}

test_varimg (){       # test if a string is a valid image file
    var=$1
    if [ "x$var" = "x" ]; then test=0; else  test=`imtest $1`; fi
    echo $test
}

test_varfile (){  # test if a string is a valid file
    var=$1
    if [ "x$var" = "x" ]; then test=0 ; elif [ ! -f $var ]; then test=0; else test=1; fi
    echo $test
}

#------------- Setting things up ----------------#


mkdir -p $outdir

## clear, then make the temporary directory
if [ -e $tmpdir ]; then /bin/rm -Rf $tmpdir;fi
mkdir $tmpdir
touch $LF

echo "Logfife for command: " >> $LF
echo $0 $@ >> $LF
echo "Run on " `date` "by user " $USER " on machine " `hostname`  >> $LF
echo "" >> $LF

#------------- verifying inputs ----------------#

if [ `test_varimg $diffusion` -eq 0 ]; then
 error_exit "ERROR: cannot find image for diffusion 4D data: $diffusion"
fi

if [ `test_varimg $dph` -eq 0 ]; then
 error_exit "ERROR: cannot find fieldmap phase image : $dph"
fi

if [ `test_varimg $mag` -eq 0 ]; then 
 error_exit "ERROR: cannot find fieldmap magnitude image: $mag"
fi

if [ `test_varimg $mask` -eq 0 ]; then 
 error_exit "ERROR: cannot find mask diffusion image: $mask" 
fi

if [ "$esp" = "PARSE_ERROR" ]; then
 error_exit "ERROR: dwell time: not set"
fi

if [ "$te" = "PARSE_ERROR" ]; then
 error_exit "ERROR: TE not set"
fi

#------------- Check dependencies ----------------#

command -v fsl > /dev/null 2>&1 || { error_exit "ERROR: FSL required, but not found (http://fsl.fmrib.ox.ac.uk/fsl). Aborting."; } 


#------------- Distortion correction using fieldmap----------------#

## copy phase and magnitude image to temporary directory
T fslmaths $dph $tmpdir/native_fmap_ph
T fslmaths $mag $tmpdir/native_fmap_mag

##copy S0 image to temporary directory, mask it, make a binary mask
T fslroi $diffusion $tmpdir/native_S0 0 1
T fslmaths $tmpdir/native_S0 -mas $mask $tmpdir/native_S0_brain
T fslmaths $tmpdir/native_S0_brain -bin $tmpdir/native_S0_brain_mask

## run bet on magnitude images or apply given mask
if [ "x${mag_mask}" = "x" ]; then 
 T bet $tmpdir/native_fmap_mag $tmpdir/native_fmap_mag_brain -m -f 0.3
 mag_mask=$tmpdir/native_fmap_mag_brain
else 
 T fslmaths $tmpdir/native_fmap_mag -mas $mag_mask $tmpdir/native_fmap_mag_brain 
 T fslmaths $mag_mask -bin $tmpdir/native_fmap_mag_brain_mask
fi

## skull-strip, dilate and smooth phase map
T fslmaths $mag_mask -bin -ero -kernel boxv 3 -mul $tmpdir/native_fmap_ph -kernel box 10 -dilM -dilM -dilM -dilM -dilM -fmedian -fmedian -s 3 $tmpdir/native_fmap_ph_filtered

## scale signal loss threshold
sl=`echo "scale=3; 1 - $sl/100" | bc`;

## scale echo time to SI units
te=`echo "scale=3; $te * 0.001" | bc`;

## Scale dwell time 
esp=`echo "scale=5; $esp/1000" | bc`

## get the median of the phase map, then subtract that from the phase map to zero the center of the distributions of the phase
T fslstats $tmpdir/native_fmap_ph_filtered -k $tmpdir/native_fmap_mag_brain_mask -P 50
v=`fslstats $tmpdir/native_fmap_ph -k $tmpdir/native_fmap_mag_brain_mask -P 50`
T fslmaths $tmpdir/native_fmap_ph_filtered -sub $v  $tmpdir/native_fmap_filtered

## calculate signal loss due to distortion
T sigloss -i $tmpdir/native_fmap_ph_filtered --te=$te -m $tmpdir/native_fmap_mag_brain_mask -s $tmpdir/native_fmap_sigloss
 
## apply the signal loss map to the field magnitude image
T fslmaths $tmpdir/native_fmap_sigloss -mul $tmpdir/native_fmap_mag_brain $tmpdir/native_fmap_mag_brain_siglossed -odt float

## warp the field magnitude image for coregistration with diffusion
T fugue -i $tmpdir/native_fmap_mag_brain_siglossed --loadfmap=$tmpdir/native_fmap_ph_filtered --mask=$tmpdir/native_fmap_mag_brain_mask --dwell=$esp -w $tmpdir/rewarped_fmap_mag_brain_siglossed --nokspace --unwarpdir=$direction

## warp the signal loss image for coregistration with diffusion
T fugue -i $tmpdir/native_fmap_sigloss --loadfmap=$tmpdir/native_fmap_ph_filtered --mask=$tmpdir/native_fmap_mag_brain_mask --dwell=$esp -w $tmpdir/rewarped_fmap_sigloss --nokspace --unwarpdir=$direction

## re-apply the signal loss threshold in the re-distorted space
T fslmaths $tmpdir/rewarped_fmap_sigloss -thr $sl $tmpdir/rewarped_fmap_sigloss


## bringing distortion correction to diffusion space 
if [ "$reg" != "n" ] ; then   ## register diffusion images to field magnitude image
 T flirt -in $tmpdir/native_S0_brain -ref $tmpdir/rewarped_fmap_mag_brain_siglossed -omat $tmpdir/diffusion_to_fieldmap.mat -o $tmpdir/native_S0_registered_to_fmap_mag -schedule $FSLDIR/etc/flirtsch/xyztrans.sch -refweight $tmpdir/rewarped_fmap_sigloss   
 T convert_xfm -omat $tmpdir/fieldmap_to_diffusion.mat -inverse $tmpdir/diffusion_to_fieldmap.mat ## invert the transformation
else                          ## if not,  make an identity transform
 echo "1 0 0 0" > $tmpdir/diffusion_to_fieldmap.mat 
 echo "0 1 0 0" >> $tmpdir/diffusion_to_fieldmap.mat 
 echo "0 0 1 0" >> $tmpdir/diffusion_to_fieldmap.mat 
 echo "0 0 0 1" >> $tmpdir/diffusion_to_fieldmap.mat 
 T cp $tmpdir/diffusion_to_fieldmap.mat $tmpdir/fieldmap_to_diffusion.mat
fi;
 
## apply transformation to phase, magnitude, mask and signal lossed images
T flirt -in $tmpdir/native_fmap_ph_filtered -ref $tmpdir/native_S0 -init $tmpdir/fieldmap_to_diffusion.mat -applyxfm -out $tmpdir/coregistered_fmap_ph
T flirt -in $tmpdir/native_fmap_mag -ref $tmpdir/native_S0 -init $tmpdir/fieldmap_to_diffusion.mat -applyxfm -out $tmpdir/coregistered_fmap_mag
T flirt -in $tmpdir/native_fmap_mag_brain -ref $tmpdir/native_S0 -init $tmpdir/fieldmap_to_diffusion.mat -applyxfm -out $tmpdir/coregistered_fmap_mag_brain
T flirt -in $tmpdir/native_fmap_mag_brain_mask -ref $tmpdir/native_S0 -init $tmpdir/fieldmap_to_diffusion.mat -applyxfm -out $tmpdir/coregistered_fmap_mag_brain_mask
T flirt -in $tmpdir/native_fmap_sigloss -ref $tmpdir/native_S0 -init $tmpdir/fieldmap_to_diffusion.mat -applyxfm -out $tmpdir/coregistered_fmap_sigloss

## threshold mask at 0.5 to make it a binary mask again after the interpolation
T fslmaths $tmpdir/coregistered_fmap_mag_brain_mask -thr 0.5 -bin $tmpdir/coregistered_fmap_mag_brain_mask -odt float

## re-apply signal loss threshold in diffusion-space
T fslmaths $tmpdir/coregistered_fmap_sigloss -thr $sl $tmpdir/coregistered_fmap_sigloss -odt float

## generate a shift map from the fieldmap 
T fugue --loadfmap=$tmpdir/coregistered_fmap_ph --dwell=$esp -i $tmpdir/native_S0 -u $tmpdir/unwarped_S0 --unwarpdir=$direction --saveshift=$tmpdir/unwarp_shift

## mask the unwarped S0
#T fslmaths $tmpdir/unwarped_S0 -mas $mask $tmpdir/unwarped_S0

## convert the shift map to a warp
T convertwarp -s $tmpdir/unwarp_shift -o $tmpdir/unwarp_warp -r $tmpdir/native_S0 --shiftdir=$direction

## apply the warp to the 4D  diffusion volume
T applywarp -i $diffusion -o $tmpdir/unwarped_`basename $diffusion` -w $tmpdir/unwarp_warp.nii.gz -r $diffusion --abs -m $mask

## TODO: unwarp the brain mask
T applywarp -i $mask -o $tmpdir/unwarped_`basename $mask` -w $tmpdir/unwarp_warp.nii.gz -r $diffusion --abs 
T fslmaths $tmpdir/unwarped_`basename $mask` -thr 0.5 -bin $tmpdir/unwarped_`basename $mask`


#--------------- copying results to output directory ------------#
T cp $tmpdir/unwarped_`basename $diffusion` $outdir/unwarped_`basename $diffusion`
T cp $tmpdir/unwarped_S0.nii.gz $outdir/unwarped_S0.nii.gz
T cp $tmpdir/unwarp_warp.nii.gz $outdir/unwarp_warp.nii.gz
T cp $tmpdir/coregistered_fmap_mag_brain_mask.nii.gz $outdir/unwarped_brain_mask.nii.gz

#--------------- generate report ------------#
if [ "$generate_report" != "n" ] ; then 
 T $scriptdir/unwarp_fieldmap_report.sh -t $tmpdir -r $reportdir -s $sl
fi

T cp $reportdir/*.html $outdir/


