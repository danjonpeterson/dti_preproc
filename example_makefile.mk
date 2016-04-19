# This makefile runs through the DTI preprocessing pipleline

# file name conventions:

# INPUT FILES
# raw_diffusion.nii.gz
# native_brain_mask.nii.gz
# bval.txt
# bvec.txt

# AND ETIHER:
# fieldmap_phase.nii.gz
# fielmap_magnitude.nii.gz

# OR:
# acqparams.txt
# index.txt

#CHANGE THIS FOR YOUR PROJECT
PROJECT_HOME= /var/local/scratch/dti_preproc_dev

cwd = $(shell pwd)
SUBJECT=$(notdir $(cwd))
BINDIR=$(PROJECT_HOME)/bin
OUTDIR=out

SDC_METHOD = $(shell if [ -f fieldmap_phase.nii.gz ] ; then echo FUGUE; \
                    elif [ -f acqparams.txt ] ; then echo TOPUP; \
                    else echo FALSE ; fi)

# Set open MP number of threads to be 1, so that we can parallelize using make.
export OMP_NUM_THREADS=1

.PHONY: PreprocessSubject tensor clean

# keep everything by default
.SECONDARY:

define dti_usage
	@echo
	@echo
	@echo Usage:
	@echo "make tensor		Makes the fa and tensor images"
	@echo "make clean		Removes everything except for the source data"
	@echo "make mostlyclean		Removes intermediate files"
	@echo
	@echo
endef

tensor: ${OUTDIR}/dti_FA.nii.gz

ifeq ($(SDC_METHOD),TOPUP)

# unwarping using topup
${OUTDIR}/topup_out_fieldcoef.nii.gz: raw_diffusion.nii.gz bval.txt bvec.txt native_brain_mask.nii.gz acqparams.txt
	${BINDIR}/dti_preproc/unwarp_bupbdown.sh -k raw_diffusion.nii.gz -b bval.txt -a acqparams.txt -M native_brain_mask.nii.gz -o ${OUTDIR} 

# motion correction from topup output
${OUTDIR}/mc_unwarped_raw_diffusion.nii.gz: raw_diffusion.nii.gz bval.txt bvec.txt native_brain_mask.nii.gz acqparams.txt index.txt ${OUTDIR}/topup_out_fieldcoef.nii.gz
	${BINDIR}/dti_preproc/motion_correct.sh -k raw_diffusion.nii.gz -b bval.txt -r bvec.txt -M native_brain_mask.nii.gz -m eddy_with_topup -i index.txt -a acqparams.txt -t ${OUTDIR}/topup_out -o ${OUTDIR}

else ifeq ($(SDC_METHOD),FUGUE)

# do just motion correction using eddy
${OUTDIR}/mc_raw_diffusion.nii.gz: raw_diffusion.nii.gz bval.txt bvec.txt native_brain_mask.nii.gz 
	${BINDIR}/dti_preproc/motion_correct.sh -k raw_diffusion.nii.gz  -b bval.txt -r bvec.txt -M native_brain_mask.nii.gz -m eddy -o ${OUTDIR} 

# unwarp a motion corrected dataset with fugue
${OUTDIR}/mc_unwarped_raw_diffusion.nii.gz: ${OUTDIR}/mc_raw_diffusion.nii.gz fieldmap_phase.nii.gz fieldmap_magnitude.nii.gz native_brain_mask.nii.gz fieldmap_magnitude_brain_mask.nii.gz
	${BINDIR}/dti_preproc/unwarp_fieldmap.sh -k ${OUTDIR}/mc_raw_diffusion.nii.gz -f fieldmap_phase.nii.gz -m fieldmap_magnitude.nii.gz -M native_brain_mask -o ${OUTDIR} -p fieldmap_magnitude_brain_mask.nii.gz -t 0.7482 -e 93.46 &&\
	mv ${OUTDIR}/unwarped_mc_raw_diffusion.nii.gz ${OUTDIR}/mc_unwarped_raw_diffusion.nii.gz 

else
$(error ERROR: neither fieldmap for FUGUE nor acquisition parameter file for TOPUP were found)
endif

# fit the tensor
${OUTDIR}/dti_FA.nii.gz: ${OUTDIR}/mc_unwarped_raw_diffusion.nii.gz bval.txt 
	${BINDIR}/dti_preproc/fit_tensor.sh -k ${OUTDIR}/mc_unwarped_raw_diffusion.nii.gz -b bval.txt -r ${OUTDIR}/bvec_mc.txt -M ${OUTDIR}/unwarped_brain_mask.nii.gz -o ${OUTDIR}

#TODO: take ${OUTDIR} values safely
clean: 
	rm -rf temp-* report-* out/

mostlyclean:
	rm -rf temp-* report-*