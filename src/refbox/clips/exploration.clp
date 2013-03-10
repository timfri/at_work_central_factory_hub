
;---------------------------------------------------------------------------
;  exploration.clp - LLSF RefBox CLIPS exploration phase rules
;
;  Created: Thu Feb 07 19:31:12 2013
;  Copyright  2013  Tim Niemueller [www.niemueller.de]
;  Licensed under BSD license, cf. LICENSE file
;---------------------------------------------------------------------------

(defrule exploration-start
  ?gf <- (gamestate (phase EXPLORATION) (prev-phase ~EXPLORATION))
  ?mf <- (machine (mtype ?mtype))
  (machine-spec (mtype ?mtype) (light-code ?lc))
  =>
  ; Set prev phase to avoid re-firing, reset game time
  (modify ?gf (prev-phase EXPLORATION) (game-time 0.0))

  ; Retract all existing reports for the new exploration phase
  (delayed-do-for-all-facts ((?report exploration-report)) TRUE
    (retract ?report)
  )

  (if (not (any-factp ((?mi machines-initialized)) TRUE))
   then (machine-init-randomize))

  ; Set lights
  (delayed-do-for-all-facts ((?machine machine)) TRUE
    (bind ?dl (create$))
    (do-for-fact ((?spec machine-spec) (?lc machine-light-code))
		 (and (eq ?machine:mtype ?spec:mtype) (= ?spec:light-code ?lc:id))
      (bind ?dl ?lc:code)
      ;(printout t "Assigning " ?lc:code " to machine " ?machine:name
      ;		   " of type " ?machine:mtype crlf)
    )
    (modify ?machine (desired-lights ?dl))
  )

  (assert (attention-message "Entering Exploration Phase" 5))
)

(defrule exploration-pause
  ?gf <- (gamestate (phase EXPLORATION) (state PAUSED) (prev-state ~PAUSED))
  =>
  (modify ?gf (prev-state PAUSED))
  (delayed-do-for-all-facts ((?machine machine)) TRUE
    (modify ?machine (desired-lights))
  )
)

(defrule exploration-continue
  ?gf <- (gamestate (phase EXPLORATION) (state RUNNING) (prev-state ~RUNNING))
  =>
  (modify ?gf (prev-state RUNNING))
  (delayed-do-for-all-facts ((?machine machine)) TRUE
    (do-for-fact ((?spec machine-spec) (?lc machine-light-code))
		 (and (eq ?machine:mtype ?spec:mtype) (= ?spec:light-code ?lc:id))
      (modify ?machine (desired-lights ?lc:code))
    )
  )
)

(defrule exploration-handle-report
  ?gf <- (gamestate (phase EXPLORATION) (points ?points) (game-time ?game-time))
  ?mf <- (protobuf-msg (type "llsf_msgs.MachineReport") (ptr ?p)
		       (rcvd-from ?from-host ?from-port) (rcvd-via ?via))
  =>
  (retract ?mf)
  (foreach ?m (pb-field-list ?p "machines")
    (bind ?name (sym-cat (pb-field-value ?m "name")))
    (bind ?type (sym-cat (pb-field-value ?m "type")))
    (if (member$ ?name (deftemplate-slot-allowed-values exploration-report name))
    then
      (do-for-fact ((?machine machine)) (eq ?machine:name ?name)
        ; If it has not been reported, yet
        (if (not (any-factp ((?report exploration-report)) (eq ?report:name ?name)))
        then
          (if (eq ?machine:mtype ?type)
          then ; correct report
	    (printout t "Correct report: " ?name " of type " ?type ". "
		      "Awarding " ?*EXPLORATION-CORRECT-REPORT-POINTS* " points" crlf) 
	    (modify ?gf (points (+ ?points ?*EXPLORATION-CORRECT-REPORT-POINTS*)))
	    (assert (exploration-report (name ?name) (type ?type) (game-time ?game-time)
					(host ?from-host) (port ?from-port)))
          else ; wrong report
	    (printout t "Wrong report: " ?name " of type " ?type ". "
		      "Penalizing with " ?*EXPLORATION-WRONG-REPORT-POINTS* " points" crlf)
	    (modify ?gf (points (max (+ ?points ?*EXPLORATION-WRONG-REPORT-POINTS*) 0)))
	    (assert (exploration-report (name ?name) (type WRONG) (game-time ?game-time)
					(host ?from-host) (port ?from-port)))
	  )
        )
      )
    )
    (pb-destroy ?m)
  )
)

(defrule exploration-cleanup-report
  (gamestate (phase ~EXPLORATION))
  ?mf <- (protobuf-msg (type "llsf_msgs.MachineReport") (ptr ?p)
		       (rcvd-from ?from-host ?from-port) (rcvd-via ?via))
  =>
  (retract ?mf)
)


(defrule exploration-send-ExplorationInfo
  (time $?now)
  (gamestate (phase EXPLORATION))
  ?sf <- (signal (type exploration-info)
		 (time $?t&:(timeout ?now ?t ?*BC-EXPLORATION-INFO-PERIOD*)) (seq ?seq))
  =>
  (modify ?sf (time ?now) (seq (+ ?seq 1)))
  (bind ?ei (pb-create "llsf_msgs.ExplorationInfo"))

  (do-for-all-facts ((?mspec machine-spec)) (<> ?mspec:light-code 0)
    (do-for-fact ((?lc machine-light-code)) (= ?mspec:light-code ?lc:id)
      (bind ?s (pb-create "llsf_msgs.ExplorationSignal"))
      (pb-set-field ?s "type" ?mspec:mtype)
      ; nested foreach are broken, hence use progn$
      (progn$ (?color (create$ RED YELLOW GREEN))
        (bind ?state OFF)
        (progn$ (?poss-state (create$ OFF ON BLINK))
          (if (member$ (sym-cat ?color "-" ?poss-state) ?lc:code)
	    then (bind ?state (str-cat ?poss-state))
          )
        )
        (bind ?s-light (pb-create "llsf_msgs.LightSpec"))
	(pb-set-field ?s-light "color" ?color)
	(pb-set-field ?s-light "state" ?state)
        (pb-add-list ?s "lights" ?s-light)
      )

      (pb-add-list ?ei "signals" ?s)
    )
  )

  (do-for-all-facts ((?m machine) (?mspec machine-spec))
    (and (eq ?m:mtype ?mspec:mtype) (<> ?mspec:light-code 0) (non-zero-pose ?m:pose))

    (bind ?em (pb-create "llsf_msgs.ExplorationMachine"))
    (pb-set-field ?em "name" ?m:name)
    (bind ?p (pb-field-value ?em "pose"))
    (bind ?p-time (pb-field-value ?p "timestamp"))
    (pb-set-field ?p-time "sec" (nth$ 1 ?m:pose-time))
    (pb-set-field ?p-time "nsec" (* (nth$ 2 ?m:pose-time) 1000))
    (pb-set-field ?p "timestamp" ?p-time)
    (pb-set-field ?p "x" (nth$ 1 ?m:pose))
    (pb-set-field ?p "y" (nth$ 2 ?m:pose))
    (pb-set-field ?p "ori" (nth$ 3 ?m:pose))
    (pb-set-field ?em "pose" ?p)
    (pb-add-list ?ei "machines" ?em)
  )

  (pb-broadcast ?ei)
  (pb-destroy ?ei)
)

(defrule exploration-send-MachineReportInfo
  (time $?now)
  (gamestate (phase EXPLORATION))
  ?sf <- (signal (type machine-report-info)
		 (time $?t&:(timeout ?now ?t ?*BC-MACHINE-REPORT-INFO-PERIOD*)) (seq ?seq))
  =>
  (modify ?sf (time ?now) (seq (+ ?seq 1)))
  (bind ?s (pb-create "llsf_msgs.MachineReportInfo"))

  (do-for-all-facts ((?report exploration-report)) TRUE
    (pb-add-list ?s "reported_machines" ?report:name)
  )

  (pb-broadcast ?s)
  (pb-destroy ?s)
)
