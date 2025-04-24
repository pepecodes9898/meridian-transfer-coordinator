;; Meridian Transfer Coordinator
;; It manages transfers between different entities with verification

;; System Administration and Status Codes
(define-constant MASTER_CONTROLLER tx-sender)
(define-constant STATUS_NO_PERMISSION (err u100))
(define-constant STATUS_ENTRY_MISSING (err u101))
(define-constant STATUS_ALREADY_PROCESSED (err u102))


;; Core Framework Data Storage
(define-map TransferEntries
  { entry-reference: uint }
  {
    origin-participant: principal,
    target-participant: principal,
    item-category: uint,
    transfer-amount: uint,
    entry-status: (string-ascii 10),
    creation-block: uint,
    expiration-block: uint
  }
)

(define-constant STATUS_ACTION_FAILED (err u103))
(define-constant STATUS_INVALID_REFERENCE (err u104))
(define-constant STATUS_INVALID_INPUT (err u105))
(define-constant STATUS_INVALID_PARTICIPANT (err u106))
(define-constant STATUS_DURATION_ENDED (err u107))
(define-constant FRAMEWORK_DURATION_BLOCKS u1008) 


;; Entry Counter
(define-data-var latest-entry-reference uint u0)

;; -------------------------------------------------------------
;; Framework Validation Methods
;; -------------------------------------------------------------

;; Check Participant Uniqueness
(define-private (check-participant-uniqueness (participant principal))
  (and 
    (not (is-eq participant tx-sender))
    (not (is-eq participant (as-contract tx-sender)))
  )
)

;; Check Entry Reference Validity
(define-private (check-entry-reference (entry-reference uint))
  (<= entry-reference (var-get latest-entry-reference))
)

;; Reclaim Resources from Expired Entry
(define-public (reclaim-expired-entry (entry-reference uint))
  (begin
    (asserts! (check-entry-reference entry-reference) STATUS_INVALID_REFERENCE)
    (let
      (
        (entry-data (unwrap! (map-get? TransferEntries { entry-reference: entry-reference }) STATUS_ENTRY_MISSING))
        (origin (get origin-participant entry-data))
        (amount (get transfer-amount entry-data))
        (expiration (get expiration-block entry-data))
      )
      (asserts! (or (is-eq tx-sender origin) (is-eq tx-sender MASTER_CONTROLLER)) STATUS_NO_PERMISSION)
      (asserts! (or (is-eq (get entry-status entry-data) "pending") (is-eq (get entry-status entry-data) "accepted")) STATUS_ALREADY_PROCESSED)
      (asserts! (> block-height expiration) (err u108)) ;; Must be expired
      (match (as-contract (stx-transfer? amount tx-sender origin))
        success
          (begin
            (map-set TransferEntries
              { entry-reference: entry-reference }
              (merge entry-data { entry-status: "expired" })
            )
            (print {event: "entry_expired_reclaimed", entry-reference: entry-reference, origin: origin, amount: amount})
            (ok true)
          )
        error STATUS_ACTION_FAILED
      )
    )
  )
)

;; Initiate Resolution Process
(define-public (initiate-resolution-process (entry-reference uint) (resolution-reasoning (string-ascii 50)))
  (begin
    (asserts! (check-entry-reference entry-reference) STATUS_INVALID_REFERENCE)
    (let
      (
        (entry-data (unwrap! (map-get? TransferEntries { entry-reference: entry-reference }) STATUS_ENTRY_MISSING))
        (origin (get origin-participant entry-data))
        (target (get target-participant entry-data))
      )
      (asserts! (or (is-eq tx-sender origin) (is-eq tx-sender target)) STATUS_NO_PERMISSION)
      (asserts! (or (is-eq (get entry-status entry-data) "pending") (is-eq (get entry-status entry-data) "accepted")) STATUS_ALREADY_PROCESSED)
      (asserts! (<= block-height (get expiration-block entry-data)) STATUS_DURATION_ENDED)
      (map-set TransferEntries
        { entry-reference: entry-reference }
        (merge entry-data { entry-status: "disputed" })
      )
      (print {event: "entry_disputed", entry-reference: entry-reference, initiator: tx-sender, reasoning: resolution-reasoning})
      (ok true)
    )
  )
)

;; Mediate Disputed Entry
(define-public (mediate-entry (entry-reference uint) (allocation-ratio uint))
  (begin
    (asserts! (check-entry-reference entry-reference) STATUS_INVALID_REFERENCE)
    (asserts! (is-eq tx-sender MASTER_CONTROLLER) STATUS_NO_PERMISSION)
    (asserts! (<= allocation-ratio u100) STATUS_INVALID_INPUT) ;; Ratio must be 0-100
    (let
      (
        (entry-data (unwrap! (map-get? TransferEntries { entry-reference: entry-reference }) STATUS_ENTRY_MISSING))
        (origin (get origin-participant entry-data))
        (target (get target-participant entry-data))
        (amount (get transfer-amount entry-data))
        (target-share (/ (* amount allocation-ratio) u100))
        (origin-share (- amount target-share))
      )
      (asserts! (is-eq (get entry-status entry-data) "disputed") (err u112)) ;; Must be disputed
      (asserts! (<= block-height (get expiration-block entry-data)) STATUS_DURATION_ENDED)

      ;; Transfer target share
      (unwrap! (as-contract (stx-transfer? target-share tx-sender target)) STATUS_ACTION_FAILED)

      ;; Transfer origin share
      (unwrap! (as-contract (stx-transfer? origin-share tx-sender origin)) STATUS_ACTION_FAILED)

      (map-set TransferEntries
        { entry-reference: entry-reference }
        (merge entry-data { entry-status: "mediated" })
      )
      (print {event: "entry_mediated", entry-reference: entry-reference, origin: origin, target: target, 
              target-share: target-share, origin-share: origin-share, allocation-ratio: allocation-ratio})
      (ok true)
    )
  )
)

