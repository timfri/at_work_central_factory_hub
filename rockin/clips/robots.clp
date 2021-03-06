;---------------------------------------------------------------------------
;  robots.clp - RoCKIn RefBox CLIPS - keeping tracks of robots in game
;
;  Copyright  2013  Tim Niemueller [www.niemueller.de]
;  Licensed under BSD license, cf. LICENSE file
;---------------------------------------------------------------------------

(defrule robot-lost
  (time $?now)
  ?rf <- (robot (team ?team) (name ?name) (host ?host) (port ?port)
    (warning-sent FALSE) (last-seen $?ls&:(timeout ?now ?ls ?*PEER-LOST-TIMEOUT*)))
  =>
  (modify ?rf (warning-sent TRUE))
  (printout warn "Robot " ?name "/" ?team " at " ?host " lost" crlf)
  (assert (attention-message (team ?team)
           (text (str-cat "Robot " ?name "/" ?team
              " at " ?host " lost"))))
)

(defrule robot-remove
  (time $?now)
  ?rf <- (robot (team ?team) (name ?name) (host ?host) (port ?port)
    (last-seen $?ls&:(timeout ?now ?ls ?*PEER-REMOVE-TIMEOUT*)))
  =>
  (retract ?rf)
  (printout warn "Robot " ?name "/" ?team " at " ?host " definitely lost" crlf)
  (assert
   (attention-message (text (str-cat "Robot " ?name "/" ?team
             " at " ?host " definitely lost"))))
)
