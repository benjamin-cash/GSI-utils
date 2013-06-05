#!/bin/ksh

#------------------------------------------------------------------
#
#  mk_angle_plots.sh
#
#  submit the plot jobs to create the angle images.
#
#  Log:
#   08/2010  safford  initial coding (adapted from angle.sh).
#------------------------------------------------------------------

set -ax
date
#export list=$listvar

export NUM_CYCLES=${NUM_CYCLES:-121}

imgndir=${IMGNDIR}/angle
tankdir=${TANKDIR}/angle

if [[ ! -d ${imgndir} ]]; then
   mkdir -p ${imgndir}
fi

echo Z = $Z

#-------------------------------------------------------------------
#  Locate/update the control files in $TANKDIR/radmon.$PDY.  $PDY 
#  starts at END_DATE and walks back to START_DATE until ctl files
#  are found or we run out of dates to check.  Report an error to 
#  the log file and exit if no ctl files are found. 
#
allmissing=1
PDY=`echo $PDATE|cut -c1-8`
ndays=$(($NUM_CYCLES/4))

for type in ${SATYPE}; do
   found=0
   done=0
   test_day=$PDATE
   ctr=$ndays
#   echo "before while loop, found, done = $found, $done"

   while [[ $found -eq 0 && $done -ne 1 ]]; do
#      echo "top of while loop"

      pdy=`echo $test_day|cut -c1-8`    
      if [[ -s ${TANKDIR}/radmon.${pdy}/angle.${type}.ctl.${Z} ]]; then
         $NCP ${TANKDIR}/radmon.${pdy}/angle.${type}.ctl.${Z} ${imgndir}/${type}.ctl.${Z}
         found=1
      elif [[ -s ${TANKDIR}/radmon.${pdy}/angle.${type}.ctl ]]; then
         $NCP ${TANKDIR}/radmon.${pdy}/angle.${type}.ctl ${imgndir}/${type}.ctl
         found=1
      fi
 
      if [[ $found -eq 0 ]]; then
         if [[ $ctr -gt 0 ]]; then
            test_day=`$NDATE -24 ${pdy}00`
            ctr=$(($ctr-1)) 
         else
            done=1
         fi
      fi
   done

   if [[ -s ${imgndir}/${type}.ctl.${Z} || -s ${imgndir}/${type}.ctl ]]; then
      allmissing=0
      found=1

#   elif [[ -s ${TANKDIR}/radmon.${PDY}/angle.${type}.ctl || -s ${TANKDIR}/radmon.${PDY}/angle.${type}.ctl.${Z} ]]; then
#      $NCP ${TANKDIR}/radmon.${PDY}/angle.${type}.ctl.${Z} ${imgndir}/${type}.ctl.${Z}
#      if [[ ! -s ${imgndir}/${type}.ctl.${Z} ]]; then
#         $NCP ${TANKDIR}/radmon.${PDY}/angle.${type}.ctl ${imgndir}/${type}.ctl
#      fi
#      allmissing=0
#      found=1
#
#   elif [[ -s ${tankdir}/${type}.ctl.${Z} || -s ${tankdir}/${type}.ctl  ]]; then
#      $NCP ${tankdir}/${type}.ctl* ${imgndir}/.
#      allmissing=0
#      found=1
#
#   else
#      echo WARNING:  unable to locate ${type}.ctl
   fi
done

if [[ $allmissing = 1 ]]; then
   echo ERROR:  Unable to plot.  All angle control files are missing from ${TANKDIR} for requested date range.
   exit
fi

# TESTING
#export SATYPE="iasi_metop-a sndrd1_g15 sndrd2_g15"
#export SATYPE="sndrd1_g15"

#-------------------------------------------------------------------
#   Update the time definition (tdef) line in the angle control 
#   files. Conditionally rm "cray_32bit_ieee" from the options line.
 
#thirtydays=`$NDATE -720 $PDATE`

for type in ${SATYPE}; do
   if [[ -s ${imgndir}/${type}.ctl.${Z} ]]; then
     ${UNCOMPRESS} ${imgndir}/${type}.ctl.${Z}
   fi
   ${SCRIPTS}/update_ctl_tdef.sh ${imgndir}/${type}.ctl ${START_DATE} ${NUM_CYCLES}

   if [[ $MY_MACHINE = "wcoss" ]]; then
      sed -e 's/cray_32bit_ieee/ /' ${imgndir}/${type}.ctl > tmp_${type}.ctl
      mv -f tmp_${type}.ctl ${imgndir}/${type}.ctl
   fi

done


for sat in ${SATYPE}; do
   nchanl=`cat ${imgndir}/${sat}.ctl | gawk '/title/{print $NF}'` 
   if [[ $nchanl -lt 100 ]]; then
      SATLIST=" $sat $SATLIST "
   else
      bigSATLIST=" $sat $bigSATLIST "
   fi
done

${COMPRESS} -f ${imgndir}/*.ctl


#-------------------------------------------------------------------
#   Rename PLOT_WORK_DIR to angle subdir.
#
  export PLOT_WORK_DIR="${PLOT_WORK_DIR}/plotangle_${SUFFIX}"

  if [[ -d $PLOT_WORK_DIR ]]; then
     rm -f $PLOT_WORK_DIR
  fi
  mkdir -p $PLOT_WORK_DIR
  cd $PLOT_WORK_DIR


  #-----------------------------------------------------------------
  # Loop over satellite types.  Submit job to make plots.
  #
  export listvar=RAD_AREA,LOADLQ,PDATE,START_DATE,NUM_CYCLES,NDATE,TANKDIR,IMGNDIR,PLOT_WORK_DIR,EXEDIR,LOGDIR,SCRIPTS,GSCRIPTS,STNMAP,GRADS,GADDIR,USER,STMP_USER,PTMP_USER,USER_CLASS,SUB,SUFFIX,SATYPE,NCP,Z,COMPRESS,UNCOMPRESS,PLOT_ALL_REGIONS,SUB_AVG,listvar

  list="count penalty omgnbc total omgbc fixang lapse lapse2 const scangl clw"

  if [[ ${MY_MACHINE} = "ccs" || ${MY_MACHINE} = "wcoss" ]]; then
     suffix=a
     cmdfile=${PLOT_WORK_DIR}/cmdfile_pangle_${suffix}
     jobname=plot_${SUFFIX}_ang_${suffix}
     logfile=$LOGDIR/plot_angle_${suffix}.log

     rm -f $cmdfile
     rm -f $logfile

     rm $LOGDIR/plot_angle_${suffix}.log
#>$cmdfile
     for type in ${SATLIST}; do
       echo "$SCRIPTS/plot_angle.sh $type $suffix '$list'" >> $cmdfile
     done
     chmod 755 $cmdfile

     ntasks=`cat $cmdfile|wc -l `

     if [[ $MY_MACHINE = "wcoss" ]]; then
        $SUB -q dev -n $ntasks -o ${logfile} -W 1:45 -J ${jobname} $cmdfile
     else
        $SUB -a $ACCOUNT -e $listvar -j ${jobname} -u $USER -t 0:45:00 -o ${logfile} -p $ntasks/1/N -q dev -g ${USER_CLASS}  /usr/bin/poe -cmdfile $cmdfile -pgmmodel mpmd -ilevel 2 -labelio yes -stdoutmode ordered
     fi
  else				# Zeus/linux platform
     for sat in ${SATLIST}; do
        suffix=${sat} 
        cmdfile=${PLOT_WORK_DIR}/cmdfile_pangle_${suffix}
        jobname=plot_${SUFFIX}_ang_${suffix}
        logfile=${LOGDIR}/plot_angle_${suffix}.log

        rm -f $cmdfile
        rm -f $logfile

        echo "$SCRIPTS/plot_angle.sh $sat $suffix '$list'" >> $cmdfile

        if [[ $PLOT_ALL_REGIONS -eq 0 ]]; then
           wall_tm="3:00:00"
        else
           wall_tm="5:00:00"
        fi

        $SUB -A $ACCOUNT -l procs=1,walltime=${wall_tm} -N ${jobname} -v $listvar -j oe -o ${logfile} ${cmdfile}
     done
  fi



  #----------------------------------------------------------------------------
  #  bigSATLIST
  #   
  #    There is so much data for some sat/instrument sources that a separate 
  #    job for each is necessary.
  #   

echo starting $bigSATLIST

set -A list count penalty omgnbc total omgbc fixang lapse lapse2 const scangl clw

for sat in ${bigSATLIST}; do
   echo processing $sat in $bigSATLIST

#
#  CCS and wcoss, submit 4 jobs for each $sat
#
   if [[ $MY_MACHINE = "ccs" || $MY_MACHINE = "wcoss" ]]; then 	
      batch=1
      ii=0

      suffix="${sat}_${batch}"
      cmdfile=${PLOT_WORK_DIR}/cmdfile_pangle_${suffix}
      rm -f $cmdfile
      jobname=plot_${SUFFIX}_ang_${suffix}
      logfile=${LOGDIR}/plot_angle_${suffix}.log

      while [[ $ii -le ${#list[@]}-1 ]]; do

         echo "$SCRIPTS/plot_angle.sh $sat $suffix ${list[$ii]}" >> $cmdfile
         (( test=ii+1 ))
         (( test=test%2 ))

         if [[ $test -eq 0 || $ii -eq ${#list[@]}-1 ]]; then
            ntasks=`cat $cmdfile|wc -l `
            chmod 755 $cmdfile

            if [[ $MY_MACHINE = "wcoss" ]]; then
               $SUB -q dev -n $ntasks -o ${logfile} -W 2:30 -J ${jobname} $cmdfile
            else
               $SUB -a $ACCOUNT -e $listvar -j ${jobname} -u $USER -t 1:00:00 -o ${logfile} -p $ntasks/1/N -q dev -g ${USER_CLASS} /usr/bin/poe -cmdfile $cmdfile -pgmmodel mpmd -ilevel 2 -labelio yes -stdoutmode ordered
            fi

            (( batch=batch+1 ))

            suffix="${sat}_${batch}"
            cmdfile=${PLOT_WORK_DIR}/cmdfile_pangle_${suffix}
            rm -f $cmdfile
            jobname=plot_${SUFFIX}_ang_${suffix}
            logfile=${LOGDIR}/plot_angle_${suffix}.log
         fi
         (( ii=ii+1 ))
      done

   else					# Zeus, submit 1 job for each sat/list item
      ii=0
      suffix="${sat}"

      while [[ $ii -le ${#list[@]}-1 ]]; do
         cmdfile=${PLOT_WORK_DIR}/cmdfile_pangle_${suffix}_${list[$ii]}
         rm -f $cmdfile
         logfile=${LOGDIR}/plot_angle_${suffix}_${list[$ii]}.log
         jobname=plot_${SUFFIX}_ang_${suffix}_${list[$ii]}

         echo "${SCRIPTS}/plot_angle.sh $sat $suffix ${list[$ii]}" >> $cmdfile

         if [[ $PLOT_ALL_REGIONS -eq 0 ]]; then
            wall_tm="2:00:00"
         else
            wall_tm="4:00:00"
         fi

         $SUB -A $ACCOUNT -l nodes=1:ppn=6,walltime=${wall_tm} -N ${jobname} -v $listvar -j oe -o ${logfile} ${cmdfile}

         (( ii=ii+1 ))
      done
  fi

done


exit
