#! /bin/sh


#---------variables and defaults---------#
dti="PARSE ERROR"                   # input DTI file
dph="PARSE ERROR"                   # B0 phase map
mag="PARSE ERROR"                   # B0 magnitude image
bval="PARSE ERROR"                  # b-values file (in FSL format)
bvec="PARSE ERROR"                  # b-vectors file (in FSL format)
mask="none"                         # brain mask file
ud=y                                    # EPI distortion direction (phase-encode direction)
SL=10                                   # signal loss threshold
outdir=.
tmpdir=temp-dti_preprocess_v2           # name of directory for intermediate files
log_filename=temp-dti_preprocess_v2.log # default log filename
skip_reslice=n                          # don't combine reslicing
mc_then_ud=n                            # order of motion correction vs undistortion  


usage_exit() {
      cat <<EOF

  Preprocess DTI data

  Version `echo "$VERSION" | awk '{print $1}'`

  Usage:   
  
    $CMD -k <img> -t <num> -e <num> -f <img> -m <img> [option]
  
    -k <img>    : DTI 4D data
    -f <img>    : B0 fieldmap image (radian/sec)
    -m <img>    : B0 fieldmap magnitude image
    -b <bvals.txt> : a text file containing a list of b-values
    -r <bvecs.txt> : a text file containing a list of b-vectors

    Option: 
    -M <img>    : mask file 
    -p <img>    : mask for magnitude image
    -u <x, x-, y, y-, z, or z->  : unwarp direction (default: y)
    -s <num>    : %signal loss threshold for B0 unwarping (default: 10)
    -t <num>    : DTI dwell time (ms - default: 0.567) 
    -e <num>    : DTI TE (ms - default: 93.46)
    -o <dir>    : output directory (defaut: current working directory)
    -n          : don't combine transforms to reslice
    -a          : do motion correction, then epi distortion correction
    -w          : use topup for epi distortion correction
    -q <file>   : acqpars file for topup
    -i <file>   : index file for topup
    -c <file>   : topup configuration file

example:

for fieldmap-based unwarping:
dti_preprocess_v2.sh -k DTI_64.nii.gz -f DTI_B0_phase.nii.gz -m DTI_B0_mag.nii.gz -b bvals -r bvecs -M brain_mask.nii.gz -p DTI_B0_mag_brain_mask -a -o preprocessed



EOF
    exit 1;
}

#------------- parsing parameters ----------------#


while getopts k:f:m:b:r:M:u:s:t:e:o:p:nawq:i:c: OPT
 do
 case "$OPT" in 
   "k" ) dti="$OPTARG";; 
   "f" ) dph="$OPTARG";;
   "m" ) mag="$OPTARG";;
   "b" ) bval="$OPTARG";;
   "r" ) bvec="$OPTARG";;
   "M" ) mask="$OPTARG";;
   "p" ) mag_mask="$OPTARG";;  
   "u" ) ud="$OPTARG";;
   "s" ) SL="$OPTARG";;
   "t" ) esp="$OPTARG";;  
   "e" ) te="$OPTARG";;
   "o" ) outdir="$OPTARG";;
   "n" ) skip_reslice=y;;
   "a" ) mc_then_ud=y;;
   "w" ) topup=y;;
   "q" ) acqparams="$OPTARG";;
   "i" ) index="$OPTARG";;
   "c" ) configfile="$OPTARG";;
    * )  usage_exit;;
 esac
done;

#------------- Utility functions ----------------#

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

#------------- Setting things up ----------------#

#TODO: verify inputs

LF=$tmpdir/$log_filename

## clear, then make the temporary directory
if [ -e $tmpdir ]; then /bin/rm -Rf $tmpdir;fi
mkdir $tmpdir
touch $LF


mkdir $outdir

## make a mask if none given
if [ "$mask" = "none" ]; then
 T bet $mag $outdir/brain -n -m
 mask="$outdir/brain_mask.nii.gz"
fi

#------------- Motion and Distortion correction ----------------#



if [ "$mc_then_ud" = "n" ]; then
 
 if [ "$topup" = "y" ]; then

  T unwarp_bupbdown.sh -k $dti -a $acqparams -M $mask -c $configfile -o $outdir
  
  T motion_correct.sh -k $dti -b $bval -r $bvec -M $mask -m eddy_with_topup -i $index -a $acqparams -t temp-unwarp_bupbdown/topup_out -o $outdir
  skip_reslice=y

 else

  T unwarp_fieldmap.sh -k $dti -f $dph -m $mag -M $mask -o $outdir -s

  T motion_correct.sh -k $outdir/unwarped_$dti -b $bval -r $bvec -o $outdir -M $mask -p $mag_mask -m eddy

 fi

else

  T motion_correct.sh -k $dti -b $bval -r $bvec -o $outdir -M $mask -m eddy

  T unwarp_fieldmap.sh -k $outdir/mc_$dti -f $dph -m $mag -M $mask -p $mag_mask -o $outdir -s

  T mv $outdir/unwarped_mc_$dti $outdir/mc_unwarped_$dti

  skip_reslice=y
fi


#------------- Reslicing ----------------------------#

if [ "$skip_reslice" = "n" ]; then
 T -e Doing Reslicing
 T reslice_dti.sh -k $dti -w $outdir/unwarp_warp.nii.gz -t $outdir/dti_ecc.mat -m $mask -o $outdir
else
 T -e Skipping reslicing
 T cp $outdir/mc_unwarped_$dti $outdir/resliced_$dti
fi

#-------------- fitting the tensor ------------------#

T fit_tensor.sh -k $outdir/resliced_$dti -b $bval -r $outdir/bvec_ecc -m $outdir/unwarped_`basename $mask` -o $outdir

