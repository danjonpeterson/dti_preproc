#! /bin/sh


#---------variables and defaults---------#
sl=10		                    # default signal loss threshold
direction=y		            # default distortion direction
tmpdir=temp-unwarp_fieldmap         # name of directory for intermediate files
LF=$tmpdir/unwarp_fieldmap.log      # default log filename
te=93.46                            # field map TE
esp=.567                            # field map echo spacing
reg=1                               # coregister between fieldmap and DTI data
outdir=.                            # put output in PWD
generate_report=y                   # generate a report 
reportdir=$tmpdir/report    # directory for html report
scriptdir=`dirname $0`

usage_exit() {
      cat <<EOF

  Correction for B0 inhomogeneity distortion

  Usage:   
  
    $CMD -k <img> -t <num> -e <num> -f <img> -m <img> [option]
      : corrects B0 inhomogeneity disortion 
  
    -k <img>    : DTI 4D data
    -f <img>    : B0 fieldmap image (radian/sec)
    -m <img>    : B0 fieldmap magnitude image
    -M <img>    : mask file 


    Option: 
    -u <x, x-, y, y-, z, or z->  : unwarp direction (default: y)
    -s <num>    : %signal loss threshold for B0 unwarping (default: 10)
    -t <num>    : DTI dwell time (ms - default: 0.567) 
    -e <num>    : DTI TE (ms - default: 93.46)
    -n          : do not register between fieldmap and dti data
    -s          : no not generate HTML report
    -o          : output directory (defaut: current working directory)
    -r          : report directory


example:
unwarp_fieldmap.sh -k DTI_64.nii.gz -f DTI_B0_phase.nii.gz -m DTI_B0_mag.nii.gz -M brain_mask.nii.gz -n

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

test_varimg (){
    var=$1
    if [ "x$var" = "x" ]; then test=0; else  test=`imtest $1`; fi
    echo $test
}

test_varfile (){
    var=$1
    if [ "x$var" = "x" ]; then test=0 ; elif [ ! -f $var ]; then test=0; else test=1; fi
    echo $test
}

#------------- Parse Parameters  --------------------#
[ "$6" = "" ] && usage_exit

while getopts k:f:m:M:u:t:e:o:r:p:ns OPT
 do
 case "$OPT" in 
   "k" ) dti="$OPTARG";; 
   "f" ) dph="$OPTARG";;
   "m" ) mag="$OPTARG";;
   "M" ) maskf="$OPTARG";;  
   "u" ) ud="$OPTARG";;
   "s" ) SL="$OPTARG";;
   "t" ) esp="$OPTARG";;  
   "e" ) te="$OPTARG";;
   "o" ) outdir="$OPTARG";;
   "n" ) reg=0;;
   "s" ) generate_report=0;;
   "r" ) reportdir="$OPTARG";;
   "p" ) mag_mask="$OPTARG";;
    * )  usage_exit;;
 esac
done;

if [ `test_varimg $dti` -eq 0 ]; then
 echo "ERROR: cannot find image for dti 4D data: $dti"
 exit 1;
fi

if [ `test_varimg $dph` -eq 0 ]; then
 echo "ERROR: cannot find image for B0 fieldmap: $dph"
 exit 1 
fi

if [ `test_varimg $mag` -eq 0 ]; then 
 echo "ERROR: cannot find image for B0 fieldmap magnitude: $mag"
 exit 1
fi

if [ `test_varimg $maskf` -eq 0 ]; then 
 echo "ERROR: cannot find image: $maskf"; 
 exit 1
fi; 


#------------- Distortion correction using fieldmap----------------#

mkdir -p $outdir

## clear, then make the temporary directory
if [ -e $tmpdir ]; then /bin/rm -Rf $tmpdir;fi
mkdir $tmpdir
touch $LF


## copy phase and magnitude image to temporary directory
T fslmaths $dph $tmpdir/native_fmap_ph
T fslmaths $mag $tmpdir/native_fmap_mag

##copy S0 image to temporary directory, mask it, make a binary mask
T fslroi $dti $tmpdir/native_S0 0 1
T fslmaths $tmpdir/native_S0 -mas $maskf $tmpdir/native_S0_brain
T fslmaths $tmpdir/native_S0_brain -bin $tmpdir/native_S0_brain_mask

## skull-strip, dilate and smooth phase map
#T fslmaths $mag_mask -bin -ero -kernel boxv 3 -mul $tmpdir/native_fmap_ph -fmedian -kernel 2D -fmedian -kernel 2D -dilM -dilM -dilM -dilM -dilM -s 3 $tmpdir/native_fmap_ph_filtered
T fslmaths $mag_mask -bin -ero -kernel boxv 3 -mul $tmpdir/native_fmap_ph -kernel box 10 -dilM -dilM -dilM -dilM -dilM -fmedian -fmedian -s 3 $tmpdir/native_fmap_ph_filtered


## run bet or apply given mask
if [ "x${mag_mask}" = "x" ]; then 
 T bet $tmpdir/native_fmap_mag $tmpdir/native_fmap_mag_brain -m -f 0.3  #TODO
else 
 T fslmaths $tmpdir/native_fmap_mag -mas $mag_mask $tmpdir/native_fmap_mag_brain 
 T fslmaths $mag_mask -bin $tmpdir/native_fmap_mag_brain_mask
fi

## scale signal loss threshold
sl=`echo "scale=3; 1 - $sl/100" | bc`;

## scale echo time to SI units
te=`echo "scale=3; $te * 0.001" | bc`;

## Scale dwell time 
esp=`echo "scale=5; $esp/1000" | bc`


## get the median of the phase map, then subtract that from the phase map - perhaps to zero the center of the distributions of the phase
T fslstats $tmpdir/native_fmap_ph_filtered -k $tmpdir/native_fmap_mag_brain_mask -P 50
v=`fslstats $tmpdir/native_fmap_ph -k $tmpdir/native_fmap_mag_brain_mask -P 50`
T fslmaths $tmpdir/native_fmap_ph_filtered -sub $v  $tmpdir/native_fmap_filtered

## calculate signal loss due to distortion
T sigloss -i $tmpdir/native_fmap_ph_filtered --te=$te -m $tmpdir/native_fmap_mag_brain_mask -s $tmpdir/native_fmap_sigloss
 
## apply the signal loss map to the field magnitude image
T fslmaths $tmpdir/native_fmap_sigloss -mul $tmpdir/native_fmap_mag_brain $tmpdir/native_fmap_mag_brain_siglossed -odt float

## warp the field magnitude image for coregistration with DTI
T fugue -i $tmpdir/native_fmap_mag_brain_siglossed --loadfmap=$tmpdir/native_fmap_ph_filtered --mask=$tmpdir/native_fmap_mag_brain_mask --dwell=$esp -w $tmpdir/rewarped_fmap_mag_brain_siglossed --nokspace --unwarpdir=$direction

## warp the signal loss image for coregistration with DTI
T fugue -i $tmpdir/native_fmap_sigloss --loadfmap=$tmpdir/native_fmap_ph_filtered --mask=$tmpdir/native_fmap_mag_brain_mask --dwell=$esp -w $tmpdir/rewarped_fmap_sigloss --nokspace --unwarpdir=$direction

## re-apply the signal loss threshold in the re-distorted space
T fslmaths $tmpdir/rewarped_fmap_sigloss -thr $sl $tmpdir/rewarped_fmap_sigloss


## bringing distortion correction to DTI space 
if [ "$reg" != "0" ] ; then   ## register DTI images to field magnitude image
 T flirt -in $tmpdir/native_S0_brain -ref $tmpdir/rewarped_fmap_mag_brain_siglossed -omat $tmpdir/dti_to_fieldmap.mat -o $tmpdir/native_S0_registered_to_fmap_mag -schedule $FSLDIR/etc/flirtsch/xyztrans.sch -refweight $tmpdir/rewarped_fmap_sigloss   
 T convert_xfm -omat $tmpdir/fieldmap_to_dti.mat -inverse $tmpdir/dti_to_fieldmap.mat ## invert the transformation
else                          ## if not,  make an identity transform
 echo "1 0 0 0" > $tmpdir/dti_to_fieldmap.mat 
 echo "0 1 0 0" >> $tmpdir/dti_to_fieldmap.mat 
 echo "0 0 1 0" >> $tmpdir/dti_to_fieldmap.mat 
 echo "0 0 0 1" >> $tmpdir/dti_to_fieldmap.mat 
 cp $tmpdir/dti_to_fieldmap.mat $tmpdir/fieldmap_to_dti.mat
fi;
 
## apply transformation to phase, magnitude, mask and signal lossed images
T flirt -in $tmpdir/native_fmap_ph_filtered -ref $tmpdir/native_S0 -init $tmpdir/fieldmap_to_dti.mat -applyxfm -out $tmpdir/coregistered_fmap_ph
T flirt -in $tmpdir/native_fmap_mag -ref $tmpdir/native_S0 -init $tmpdir/fieldmap_to_dti.mat -applyxfm -out $tmpdir/coregistered_fmap_mag
T flirt -in $tmpdir/native_fmap_mag_brain -ref $tmpdir/native_S0 -init $tmpdir/fieldmap_to_dti.mat -applyxfm -out $tmpdir/coregistered_fmap_mag_brain
T flirt -in $tmpdir/native_fmap_mag_brain_mask -ref $tmpdir/native_S0 -init $tmpdir/fieldmap_to_dti.mat -applyxfm -out $tmpdir/coregistered_fmap_mag_brain_mask
T flirt -in $tmpdir/native_fmap_sigloss -ref $tmpdir/native_S0 -init $tmpdir/fieldmap_to_dti.mat -applyxfm -out $tmpdir/coregistered_fmap_sigloss

## threshold mask at 0.5 to make it a binary mask again after the interpolation
T fslmaths $tmpdir/coregistered_fmap_mag_brain_mask -thr 0.5 -bin $tmpdir/coregistered_fmap_mag_brain_mask -odt float

## re-apply signal loss threshold in DTI-space
T fslmaths $tmpdir/coregistered_fmap_sigloss -thr $sl $tmpdir/coregistered_fmap_sigloss -odt float

## generate a shift map from the fieldmap 
T fugue --loadfmap=$tmpdir/coregistered_fmap_ph --dwell=$esp -i $tmpdir/native_S0 -u $tmpdir/unwarped_S0 --unwarpdir=$direction --saveshift=$tmpdir/unwarp_shift

## mask the unwarped S0
#T fslmaths $tmpdir/unwarped_S0 -mas $maskf $tmpdir/unwarped_S0

## convert the shift map to a warp
T convertwarp -s $tmpdir/unwarp_shift -o $tmpdir/unwarp_warp -r $tmpdir/native_S0 --shiftdir=$direction

## apply the warp to the 4D  DTI volume
T applywarp -i $dti -o $tmpdir/unwarped_`basename $dti` -w $tmpdir/unwarp_warp.nii.gz -r $dti --abs -m $maskf

## TODO: unwarp the brain mask
T applywarp -i $maskf -o $tmpdir/unwarped_`basename $maskf` -w $tmpdir/unwarp_warp.nii.gz -r $dti --abs 
T fslmaths $tmpdir/unwarped_`basename $maskf` -thr 0.5 -bin $tmpdir/unwarped_`basename $maskf`

## final output
T cp $tmpdir/unwarped_`basename $dti` $outdir/unwarped_`basename $dti`
T cp $tmpdir/unwarped_S0.nii.gz $outdir/unwarped_S0.nii.gz
T cp $tmpdir/unwarp_warp.nii.gz $outdir/unwarp_warp.nii.gz
T cp $tmpdir/coregistered_fmap_mag_brain_mask.nii.gz $outdir/unwarped_brain_mask.nii.gz

## generate report
if [ "$generate_report" != "n" ] ; then 
 T $scriptdir/unwarp_fieldmap_report.sh -t $tmpdir -r $reportdir -s $sl
fi

cp $reportdir/*.html $outdir/



