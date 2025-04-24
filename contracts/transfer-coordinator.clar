;; Meridian Transfer Coordinator
;; It manages transfers between different entities with verification

;; System Administration and Status Codes
(define-constant MASTER_CONTROLLER tx-sender)
(define-constant STATUS_NO_PERMISSION (err u100))
(define-constant STATUS_ENTRY_MISSING (err u101))
(define-constant STATUS_ALREADY_PROCESSED (err u102))

