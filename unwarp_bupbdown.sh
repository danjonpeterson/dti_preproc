#! /bin/sh

usage_exit() {
      cat <<EOF

  Correction for susceptibility-induced distortions using topup

  example usage:   
  
    unwarp_bupbdown.sh -k diffusion_data.nii.gz -a acqpars.txt -M brain_mask.nii.gz -b bval.txt
 
    Required:  
    -k <img>          : 4D diffusion image
    -a <text>         : eddy/topup acquisition parameters file
    -M <img>          : mask file

    and either/or
    -b <text>         : b-value file
    -n <number>       : number of S0 volumes

    Optional: 
    -s               : no not generate HTML report
    -o <directory>   : output directory (defaut: current working directory)
    -c <file.cnf>    : topup config file
    -E               : don't run the commands, just echo them
    -F               : fast mode for testing (minimal iterations)

EOF
    exit 1;
}

#---------variables and defaults---------#
direction=y                         # distortion direction
tmpdir=temp-unwarp_bupbdown         # name of directory for intermediate files
LF=$tmpdir/unwarp_bupbdown.log      # log filename
outdir=.                            # output directory
generate_report=y                   # generate a report 
reportdir=$tmpdir/report            # directory for html report
configfile=b02b0.cnf                # config file. b02b0.cnf actually lives in ${FSLDIR}/etc/flirtsch/
scriptdir=`dirname $0`              # directory where dti_preproc scripts live
mode=normal                         # run mode (normal,echo)
fast_testing=n                      # run with minimal processing for testing

#---------------- Utility Functions --------------#

T () {    # main shell commands are run through here

 E=0 
 if [ "$1" = "-e" ] ; then  # just outputting and logging a message with T -e 
  E=1; shift  
 fi
 
 cmd="$*"
 echo $* | tee -a $LF       # read the command into the console, and the log file

 if [ "$E" != "1" ] && [ "$mode" != "echo" ] ; then 
  $cmd 2>&1 | tee -a $LF    # run the command. read the output into a the log file. Stderr is not directed to the logfile
 fi

 echo  | tee -a $LF         # write an empty line to the console and log file
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

#------------- Parse Parameters  --------------------#
[ "$4" = "" ] && usage_exit  #show help message if fewer than four args

while getopts k:a:M:so:r:c:b:n:EF OPT
 do
 case "$OPT" in 
   "k" ) diffusion="$OPTARG";; 
   "a" ) acqparams="$OPTARG";; 
   "M" ) mask="$OPTARG";;  
   "s" ) generate_report=n;;
   "o" ) outdir="$OPTARG";;
   "r" ) reportdir="$OPTARG";;
   "c" ) configfile="$OPTARG";;
   "b" ) bval="$OPTARG";;
   "n" ) S0_count="$OPTARG";;
   "E" ) mode=echo;;
   "F" ) fast_testing=y;;
    * )  usage_exit;;
 esac
done;

#------------- Setting things up ----------------#

## clear, then make the temporary directory
if [ -e $tmpdir ]; then /bin/rm -Rf $tmpdir;fi
mkdir $tmpdir
touch $LF

## make the output directory
T mkdir -p $outdir

if [ "$mode" = "echo" ]; then
  T -e "Running in echo mode - no actual processing done"
fi

#------------- verifying inputs ----------------#

if [ `test_varimg $diffusion` -eq 0 ]; then
 error_exit "ERROR: cannot find image for 4D diffusion data: $diffusion"
fi

if [ `test_varimg $mask` -eq 0 ]; then 
 error_exit "ERROR: cannot find image: $mask"; 
fi; 

if [ `test_varfile $acqparams` -eq 0 ]; then 
 error_exit "ERROR: cannot find acqparams file: $acqparams"; 
fi; 

if [ `test_varfile $bval` -eq 0 ] && [ -z "$S0_count" ]; then 
 T -e "ERROR: no valid b-value file, nor S0 count"; 
 usage_exit
fi

#------------- Check dependencies ----------------#

command -v fsl > /dev/null 2>&1 || { error_exit "ERROR: FSL required, but not found (http://fsl.fmrib.ox.ac.uk/fsl). Aborting."; } 


#--------- Distortion correction using blip up-blip down S0 images-------#

echo "Logfife for command: " >> $LF
echo $0 $@ >> $LF
echo "Run on " `date` "by user " $USER " on machine " `hostname`  >> $LF
echo "" >> $LF

if [ "$fast_testing" = "y" ]; then
  configfile=$scriptdir/b02b0_fast.cnf
fi

## count number of S0 volumes if not supplied
if [ -z "$S0_count" ]; then
 S0_count=`cat $bval | tr ' ' '\n' | grep -c ^0`
fi

T -e "count of S0 volumes is: $S0_count"

T fslroi $diffusion $tmpdir/S0_images 0 $S0_count

## do the thing
T topup --imain=$tmpdir/S0_images --datain=$acqparams --config=$configfile --out=$tmpdir/topup_out --fout=$tmpdir/field_est --iout=$tmpdir/unwarped_S0_images --verbose

## remake mask after unwarping from mean S0 image
T fslmaths $tmpdir/unwarped_S0_images -Tmean $tmpdir/avg_unwarped_S0
T bet $tmpdir/avg_unwarped_S0 $tmpdir/unwarped_brain -m -f 0.2

#--------------- copying results to output directory ------------#

T cp $tmpdir/topup_out* $outdir/
T cp $tmpdir/unwarped_brain_mask.nii.gz $outdir/

#--------------- generate report ------------#
if [ "$generate_report" != "n" ] ; then 
 T $scriptdir/unwarp_bupbdown_report.sh -t $tmpdir -r $reportdir -o $outdir
fi

T cp $reportdir/*.html $outdir
