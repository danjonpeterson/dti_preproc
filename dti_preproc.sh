#! /bin/sh

usage_exit() {
      cat <<EOF

  Preprocess DTI Data

    Examples:  

       for fieldmap-based unwarping:
      dti_preproc.sh -k raw_diffusion.nii.gz -b bval.txt -r bvec.txt -M brain_mask.nii.gz \\
                     -f fieldmap_phase.nii.gz -m fieldmap_magnitude.nii.gz \\
                     -p fieldmap_magnitude_brain_mask -e 93.46 -t 0.567

       for blipup-blipbdown based unwarping:
      dti_preproc.sh -k raw_diffusion.nii.gz -b bval.txt -r bvec.txt -M brain_mask.nii.gz \\
                     -q acqparams.txt -i index.txt
  
    Required:
    -k <img>      : DTI 4D data
    -b <bval.txt> : a text file containing a list of b-values 
                    (fsl format - one line)
    -r <bvec.txt> : a text file containing a list of b-vectors 
                    (fsl format - three lines)
    -M <img>      : mask file 

    And either: 
    -f <img>      : fieldmap image (radian/sec)
    -m <img>      : fieldmap magnitude image
    -e <num>      : DTI TE (in ms)
    -t <num>      : DTI dwell time (in ms) 
    -p <img>      : mask for magnitude image

    Or:
    -q <file>     : acqpars file for topup
    -i <file>     : index file for topup

    Optional: 
    -c <file>     : topup configuration file
    -s <num>      : % signal loss threshold for fieldmap-based unwarping (default: 10)
    -o <dir>      : output directory (defaut: current working directory)
    -E            : don't run the commands, just echo them
    -F            : fast mode for testing (minimal iterations)

On github: https://github.com/danjonpeterson/dti_preproc.git

EOF
    exit 1;
}

#---------variables and defaults---------#
diffusion="PARSE_ERROR_dti"       # input raw diffusion file
dph="PARSE_ERROR_dph"             # fieldmap phase map
mag="PARSE_ERROR_mag"             # fieldmap magnitude image
bval="PARSE_ERROR_bval"           # b-values file (in FSL format)
bvec="PARSE_ERROR_vec"            # b-vectors file (in FSL format)
mask="PARSE_ERROR_mask"           # brain mask file for diffusion data
method="PARSE_ERROR_method"       # topup or fugue
bvec_rotation=y                   # rotate bvecs according to motion correction transforms
configfile=b02b0.cnf              # config file. b02b0.cnf actually lives in ${FSLDIR}/etc/flirtsch/
SL=10                             # signal loss threshold
outdir=out                        # output directory
LF=$outdir/dti_preproc.log        # default log filename
mode=normal                       # run mode (normal,echo)
fast_testing=n                    # run with minimal processing for testing
scriptdir=`dirname $0`            # directory where dti_preproc scripts live
other_opts=""                     # flags to pass onto the sub-commands

#------------- parsing parameters ----------------#
if [ "$6" = "" ]; then usage_exit; fi  #show help message if fewer than six args

while getopts k:b:r:M:f:m:e:t:p:q:i:c:s:o:EF OPT
 do
 case "$OPT" in 
   "k" ) diffusion="$OPTARG";; 
   "b" ) bval="$OPTARG";;
   "r" ) bvec="$OPTARG";;
   "M" ) mask="$OPTARG";; 
   "f" ) dph="$OPTARG"
         method="fugue";;
   "m" ) mag="$OPTARG";;
   "p" ) mag_mask="$OPTARG";;  
   "t" ) esp="$OPTARG";;  
   "e" ) te="$OPTARG";;
   "q" ) acqparams="$OPTARG"
         method="topup";;
   "i" ) index="$OPTARG";;
   "c" ) configfile="$OPTARG";;
   "s" ) SL="$OPTARG";;   
   "o" ) outdir="$OPTARG";;
   "E" ) mode=echo;;
   "F" ) fast_testing=y;;
    * )  usage_exit;;
 esac
done;

#------------- Utility functions ----------------#

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
    echo "$1" >&2   # Send message to stderr
    echo "$1" >> $LF # send message to log file
    exit "${2:-1}"  # Return a code specified by $2 or 1 by default.
}

test_varimg (){   # test if a string is a valid image file
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

## make the output directory
T mkdir -p $outdir

## clear, then make the logfile
if [ -e $LF ]; then /bin/rm -f $LF ;fi
touch $LF

echo "Logfife for command: " >> $LF
echo $0 $@ >> $LF
echo "Run on " `date` "by user " $USER " on machine " `hostname`  >> $LF
echo "" >> $LF


if [ "$mode" = "echo" ]; then
  T -e "Running in echo mode - no actual processing done"
fi

if [ "$fast_testing" = "y" ]; then
  other_opts=`echo $other_opts -F`
fi

#------------- verifying inputs ----------------#

if [ `test_varimg $diffusion` -eq 0 ]; then
  error_exit "ERROR: cannot find image for 4D raw diffusion data: $diffusion"
else
  dtidim4=`fslval $diffusion dim4`
fi

if [ `test_varfile $bvec` -eq 0 ]; then error_exit "ERROR: $bvec is not a valid bvec file"; fi

bvecl=`cat $bvec | awk 'END{print NR}'`
bvecw=`cat $bvec | wc -w` 
if [ $bvecl != 3 ]; then error_exit "ERROR: bvecs file contains $bvecl lines, it should be 3 lines, each for x, y, z"; fi
if [ "$bvecw" != "`expr 3 \* $dtidim4`" ]; then error_exit "ERROR: bvecs file contains $bvecw words, it should be 3 x $dtidim4 = `expr 3 \* $dtidim4` words"; fi

if [ `test_varfile $bval` -eq 0 ]; then error_exit "ERROR: $bval is not a valid bvals file"; fi

bvall=`cat $bval | awk 'END{print NR}'`; bvalw=`cat $bval | wc -w`
if [ $bvall != 1 ]; then error_exit "ERROR: bvals file contains $bvall lines, it should be 1 lines"; fi
if [ $bvalw != $dtidim4 ]; then error_exit "ERROR: bval file contains $bvalw words, it should be $dtidim4 words"; fi 

if [ `test_varimg $mask` -eq 0 ]; then 
 error_exit "ERROR: cannot find mask image: $mask" 
fi

if [ "$method" = "topup" ]; then

  if [ `test_varfile $index` -eq 0 ]; then error_exit "ERROR: $index is not a valid index file"; fi
  if [ `test_varfile $acqparams` -eq 0 ]; then error_exit "ERROR: $acqparams is not a valid acquision parameters file"; fi

elif [ "$method" = "fugue" ]; then

  if [ `test_varimg $dph` -eq 0 ]; then error_exit "ERROR: cannot find image for fieldmap phase: $dph"; fi
  if [ `test_varimg $mag` -eq 0 ]; then error_exit "ERROR: cannot find image for fieldmap magnitude: $mag"; fi
  if [ `test_varimg $mag_mask` -eq 0 ]; then error_exit "ERROR: cannot find image for fieldmap magnitude mask: $mag_mask"; fi

else
  error_exit "ERROR: method \"$method\" is neither topup nor fugue"
fi


#------------- Motion and Distortion correction ----------------#
 
if [ "$method" = "topup" ]; then

  T -e "Unwarping distortions based on blipup-blipbdown data"

  T $scriptdir/unwarp_bupbdown.sh -k $diffusion -a $acqparams -M $mask -c $configfile -o $outdir -b $bval $other_opts
  
  T $scriptdir/motion_correct.sh -k $diffusion -b $bval -r $bvec -M $mask -i $index -a $acqparams -t temp-unwarp_bupbdown/topup_out -o $outdir $other_opts

  diffusion=$outdir/mc_unwarped_$diffusion

elif [ "$method" = "fugue" ]; then

  T -e "Unwarping distortions based on an acquired fieldmap"

  T $scriptdir/motion_correct.sh -k $diffusion -b $bval -r $bvec -o $outdir -M $mask $other_opts

  T $scriptdir/unwarp_fieldmap.sh -k $outdir/mc_$diffusion -f $dph -m $mag -M $mask -p $mag_mask -o $outdir -s $SL -t $esp -e $te  $other_opts

  diffusion=$outdir/unwarped_mc_$diffusion

else

  error_exit "ERROR: method \"$method\" is neither topup nor fugue"

fi

#-------------- fitting the tensor ------------------#

if [ "$bvec_rotation" = "y" ]; then
  bvec=$outdir/bvec_mc.txt
fi

T $scriptdir/fit_tensor.sh -k $diffusion -b $bval -r $bvec -M $outdir/unwarped_brain_mask.nii.gz -o $outdir $other_opts

T -e "Inspect results with the following command:"
T -e "firefox $outdir/\*html "
