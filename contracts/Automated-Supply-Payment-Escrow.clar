(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-insufficient-funds (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-invalid-status (err u104))
(define-constant err-delivery-not-confirmed (err u105))
(define-constant err-escrow-expired (err u106))
(define-constant err-already-exists (err u107))
(define-constant err-invalid-amount (err u108))
(define-constant err-cannot-cancel (err u109))
(define-constant err-invalid-partial-amount (err u110))
(define-constant err-insufficient-remaining-balance (err u111))
(define-constant err-reputation-not-found (err u112))
(define-constant err-no-escrows-completed (err u113))
(define-constant err-milestone-not-found (err u114))
(define-constant err-milestone-already-completed (err u115))
(define-constant err-all-milestones-not-completed (err u116))
(define-constant err-invalid-milestone-count (err u117))
(define-constant err-dispute-already-exists (err u118))
(define-constant err-dispute-not-found (err u119))
(define-constant err-dispute-already-resolved (err u120))
(define-constant err-invalid-resolution (err u121))

(define-data-var escrow-counter uint u0)
(define-data-var dispute-counter uint u0)
(define-data-var on-time-delivery-bonus uint u10)
(define-data-var dispute-penalty int -20)
(define-data-var successful-escrow-bonus uint u5)

(define-map escrows 
  uint 
  {
    buyer: principal,
    supplier: principal,
    amount: uint,
    description: (string-ascii 500),
    status: (string-ascii 20),
    created-at: uint,
    delivery-deadline: uint,
    delivery-confirmed-at: (optional uint),
    cancelled-at: (optional uint)
  }
)

(define-map delivery-confirmations
  uint
  {
    confirmer: principal,
    confirmed-at: uint,
    notes: (string-ascii 200)
  }
)

(define-map escrow-balances
  uint
  uint
)

(define-map user-escrows
  principal
  (list 100 uint)
)

(define-map partial-releases
  uint
  (list 50 {
    amount: uint,
    released-at: uint,
    released-by: principal
  })
)

(define-map supplier-reputation
  principal
  {
    total-escrows: uint,
    successful-escrows: uint,
    disputed-escrows: uint,
    on-time-deliveries: uint,
    total-volume: uint,
    reputation-score: int,
    last-updated: uint
  }
)

(define-map reputation-history
  { supplier: principal, escrow-id: uint }
  {
    score-change: int,
    event-type: (string-ascii 30),
    timestamp: uint
  }
)

(define-map supplier-tier
  principal
  {
    tier: uint,
    tier-name: (string-ascii 20),
    unlocked-at: uint
  }
)

(define-map escrow-milestones
  uint
  (list 10 {
    milestone-id: uint,
    description: (string-ascii 200),
    payment-percentage: uint,
    completed: bool,
    completed-at: (optional uint)
  })
)

(define-map escrow-disputes
  uint
  {
    dispute-id: uint,
    escrow-id: uint,
    initiator: principal,
    reason: (string-ascii 500),
    buyer-evidence: (string-ascii 500),
    supplier-evidence: (string-ascii 500),
    status: (string-ascii 20),
    resolution: (string-ascii 20),
    buyer-refund-percentage: uint,
    created-at: uint,
    resolved-at: (optional uint),
    resolved-by: (optional principal)
  }
)

(define-map dispute-by-escrow
  uint
  uint
)

(define-public (create-escrow 
  (supplier principal) 
  (description (string-ascii 500)) 
  (delivery-days uint))
  (let
    (
      (escrow-id (+ (var-get escrow-counter) u1))
      (amount (stx-get-balance tx-sender))
      (current-height burn-block-height)
      (deadline (+ current-height (* delivery-days u144)))
    )
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (> delivery-days u0) err-invalid-amount)
    (asserts! (not (is-eq tx-sender supplier)) err-unauthorized)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (map-set escrows escrow-id {
      buyer: tx-sender,
      supplier: supplier,
      amount: amount,
      description: description,
      status: "active",
      created-at: current-height,
      delivery-deadline: deadline,
      delivery-confirmed-at: none,
      cancelled-at: none
    })
    
    (map-set escrow-balances escrow-id amount)
    
    (map-set user-escrows tx-sender 
      (unwrap! (as-max-len? 
        (append (default-to (list) (map-get? user-escrows tx-sender)) escrow-id) 
        u100) 
        err-invalid-amount))
    
    (map-set user-escrows supplier
      (unwrap! (as-max-len? 
        (append (default-to (list) (map-get? user-escrows supplier)) escrow-id) 
        u100) 
        err-invalid-amount))
    
    (if (is-none (map-get? supplier-reputation supplier))
      (map-set supplier-reputation supplier 
        {
          total-escrows: u0,
          successful-escrows: u0,
          disputed-escrows: u0,
          on-time-deliveries: u0,
          total-volume: u0,
          reputation-score: 0,
          last-updated: burn-block-height
        })
      true)
    
    (var-set escrow-counter escrow-id)
    (ok escrow-id)
  )
)

(define-public (confirm-delivery (escrow-id uint) (notes (string-ascii 200)))
  (let
    (
      (escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found))
      (current-height burn-block-height)
    )
    (asserts! (is-eq tx-sender (get buyer escrow-data)) err-unauthorized)
    (asserts! (is-eq (get status escrow-data) "active") err-invalid-status)
    (asserts! (<= current-height (get delivery-deadline escrow-data)) err-escrow-expired)
    
    (map-set delivery-confirmations escrow-id {
      confirmer: tx-sender,
      confirmed-at: current-height,
      notes: notes
    })
    
    (map-set escrows escrow-id (merge escrow-data {
      status: "delivered",
      delivery-confirmed-at: (some current-height)
    }))
    
    (ok true)
  )
)

(define-public (release-payment (escrow-id uint))
  (let
    (
      (escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found))
      (escrow-balance (unwrap! (map-get? escrow-balances escrow-id) err-not-found))
      (current-height burn-block-height)
    )
    (asserts! (or 
      (is-eq tx-sender (get buyer escrow-data))
      (is-eq tx-sender (get supplier escrow-data))
      (is-eq tx-sender contract-owner)) err-unauthorized)
    (asserts! (is-eq (get status escrow-data) "delivered") err-delivery-not-confirmed)
    (asserts! (is-some (get delivery-confirmed-at escrow-data)) err-delivery-not-confirmed)
    (asserts! (> escrow-balance u0) err-insufficient-funds)
    
    (try! (as-contract (stx-transfer? escrow-balance tx-sender (get supplier escrow-data))))
    
    (map-set escrows escrow-id (merge escrow-data {
      status: "completed"
    }))
    
    (map-set escrow-balances escrow-id u0)
    
    (try! (update-supplier-reputation (get supplier escrow-data) escrow-id "success"))
    
    (ok escrow-balance)
  )
)

(define-public (cancel-escrow (escrow-id uint))
  (let
    (
      (escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found))
      (escrow-balance (unwrap! (map-get? escrow-balances escrow-id) err-not-found))
      (current-height burn-block-height)
    )
    (asserts! (is-eq tx-sender (get buyer escrow-data)) err-unauthorized)
    (asserts! (is-eq (get status escrow-data) "active") err-cannot-cancel)
    (asserts! (> current-height (get delivery-deadline escrow-data)) err-cannot-cancel)
    (asserts! (> escrow-balance u0) err-insufficient-funds)
    
    (try! (as-contract (stx-transfer? escrow-balance tx-sender (get buyer escrow-data))))
    
    (map-set escrows escrow-id (merge escrow-data {
      status: "cancelled",
      cancelled-at: (some current-height)
    }))
    
    (map-set escrow-balances escrow-id u0)
    
    (ok escrow-balance)
  )
)

(define-public (dispute-escrow (escrow-id uint))
  (let
    (
      (escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found))
    )
    (asserts! (or 
      (is-eq tx-sender (get buyer escrow-data))
      (is-eq tx-sender (get supplier escrow-data))) err-unauthorized)
    (asserts! (is-eq (get status escrow-data) "active") err-invalid-status)
    
    (map-set escrows escrow-id (merge escrow-data {
      status: "disputed"
    }))
    
    (try! (update-supplier-reputation (get supplier escrow-data) escrow-id "dispute"))
    
    (ok true)
  )
)

(define-public (resolve-dispute (escrow-id uint) (release-to-supplier bool))
  (let
    (
      (escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found))
      (escrow-balance (unwrap! (map-get? escrow-balances escrow-id) err-not-found))
      (recipient (if release-to-supplier (get supplier escrow-data) (get buyer escrow-data)))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-eq (get status escrow-data) "disputed") err-invalid-status)
    (asserts! (> escrow-balance u0) err-insufficient-funds)
    
    (try! (as-contract (stx-transfer? escrow-balance tx-sender recipient)))
    
    (map-set escrows escrow-id (merge escrow-data {
      status: "resolved"
    }))
    
    (map-set escrow-balances escrow-id u0)
    
    (ok recipient)
  )
)

(define-public (extend-deadline (escrow-id uint) (additional-days uint))
  (let
    (
      (escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found))
      (current-height burn-block-height)
      (new-deadline (+ (get delivery-deadline escrow-data) (* additional-days u144)))
    )
    (asserts! (is-eq tx-sender (get buyer escrow-data)) err-unauthorized)
    (asserts! (is-eq (get status escrow-data) "active") err-invalid-status)
    (asserts! (> additional-days u0) err-invalid-amount)
    
    (map-set escrows escrow-id (merge escrow-data {
      delivery-deadline: new-deadline
    }))
    
    (ok new-deadline)
  )
)

(define-read-only (get-escrow (escrow-id uint))
  (map-get? escrows escrow-id)
)

(define-read-only (get-escrow-balance (escrow-id uint))
  (map-get? escrow-balances escrow-id)
)

(define-read-only (get-delivery-confirmation (escrow-id uint))
  (map-get? delivery-confirmations escrow-id)
)

(define-read-only (get-user-escrows (user principal))
  (default-to (list) (map-get? user-escrows user))
)

(define-read-only (get-escrow-count)
  (var-get escrow-counter)
)

(define-read-only (is-escrow-expired (escrow-id uint))
  (match (map-get? escrows escrow-id)
    escrow-data (> burn-block-height (get delivery-deadline escrow-data))
    false
  )
)

(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender))
)

(define-read-only (calculate-time-remaining (escrow-id uint))
  (match (map-get? escrows escrow-id)
    escrow-data 
      (let ((current-height burn-block-height)
            (deadline (get delivery-deadline escrow-data)))
        (if (< current-height deadline)
          (some (- deadline current-height))
          (some u0)))
    none
  )
)

(define-public (release-partial-payment (escrow-id uint) (partial-amount uint))
  (let
    (
      (escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found))
      (escrow-balance (unwrap! (map-get? escrow-balances escrow-id) err-not-found))
      (current-height burn-block-height)
      (current-releases (default-to (list) (map-get? partial-releases escrow-id)))
    )
    (asserts! (is-eq tx-sender (get buyer escrow-data)) err-unauthorized)
    (asserts! (is-eq (get status escrow-data) "active") err-invalid-status)
    (asserts! (> partial-amount u0) err-invalid-partial-amount)
    (asserts! (<= partial-amount escrow-balance) err-insufficient-remaining-balance)
    
    (try! (as-contract (stx-transfer? partial-amount tx-sender (get supplier escrow-data))))
    
    (map-set partial-releases escrow-id
      (unwrap! (as-max-len?
        (append current-releases {
          amount: partial-amount,
          released-at: current-height,
          released-by: tx-sender
        })
        u50)
        err-invalid-partial-amount))
    
    (map-set escrow-balances escrow-id (- escrow-balance partial-amount))
    
    (ok partial-amount)
  )
)

(define-read-only (get-partial-releases (escrow-id uint))
  (default-to (list) (map-get? partial-releases escrow-id))
)

(define-read-only (get-total-released (escrow-id uint))
  (fold calculate-total-released (default-to (list) (map-get? partial-releases escrow-id)) u0)
)

(define-private (calculate-total-released (release {amount: uint, released-at: uint, released-by: principal}) (total uint))
  (+ total (get amount release))
)

(define-private (update-supplier-reputation (supplier principal) (escrow-id uint) (event-type (string-ascii 30)))
  (let
    (
      (reputation (unwrap! (map-get? supplier-reputation supplier) err-reputation-not-found))
      (escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found))
      (score-change (get-score-change event-type escrow-data))
      (new-score (+ (get reputation-score reputation) score-change))
      (is-on-time (is-on-time-delivery escrow-data))
    )
    (map-set supplier-reputation supplier 
      (merge reputation {
        total-escrows: (+ (get total-escrows reputation) u1),
        successful-escrows: (if (is-eq event-type "success") (+ (get successful-escrows reputation) u1) (get successful-escrows reputation)),
        disputed-escrows: (if (is-eq event-type "dispute") (+ (get disputed-escrows reputation) u1) (get disputed-escrows reputation)),
        on-time-deliveries: (if is-on-time (+ (get on-time-deliveries reputation) u1) (get on-time-deliveries reputation)),
        total-volume: (+ (get total-volume reputation) (get amount escrow-data)),
        reputation-score: new-score,
        last-updated: burn-block-height
      }))
    
    (map-set reputation-history { supplier: supplier, escrow-id: escrow-id } {
      score-change: score-change,
      event-type: event-type,
      timestamp: burn-block-height
    })
    
    (unwrap-panic (update-supplier-tier supplier new-score))
    (ok true)
  )
)

(define-private (get-score-change (event-type (string-ascii 30)) (escrow-data {buyer: principal, supplier: principal, amount: uint, description: (string-ascii 500), status: (string-ascii 20), created-at: uint, delivery-deadline: uint, delivery-confirmed-at: (optional uint), cancelled-at: (optional uint)}))
  (if (is-eq event-type "success")
    (if (is-on-time-delivery escrow-data)
      (to-int (+ (var-get successful-escrow-bonus) (var-get on-time-delivery-bonus)))
      (to-int (var-get successful-escrow-bonus)))
    (if (is-eq event-type "dispute")
      (var-get dispute-penalty)
      0
    )
  )
)

(define-private (is-on-time-delivery (escrow-data {buyer: principal, supplier: principal, amount: uint, description: (string-ascii 500), status: (string-ascii 20), created-at: uint, delivery-deadline: uint, delivery-confirmed-at: (optional uint), cancelled-at: (optional uint)}))
  (match (get delivery-confirmed-at escrow-data)
    confirmed-at (<= confirmed-at (get delivery-deadline escrow-data))
    false
  )
)

(define-private (update-supplier-tier (supplier principal) (score int))
  (let
    (
      (current-tier (default-to { tier: u0, tier-name: "Bronze", unlocked-at: u0 } (map-get? supplier-tier supplier)))
      (new-tier (get-new-tier score))
    )
    (if (> (get tier new-tier) (get tier current-tier))
      (begin (map-set supplier-tier supplier new-tier) (ok true))
      (ok true))
  )
)

(define-private (get-new-tier (score int))
  (if (>= score 100)
    { tier: u3, tier-name: "Platinum", unlocked-at: burn-block-height }
    (if (>= score 50)
      { tier: u2, tier-name: "Gold", unlocked-at: burn-block-height }
      (if (>= score 10)
        { tier: u1, tier-name: "Silver", unlocked-at: burn-block-height }
        { tier: u0, tier-name: "Bronze", unlocked-at: burn-block-height }
      )
    )
  )
)

(define-public (set-reputation-parameters (on-time-bonus uint) (dispute-penalty-val int) (success-bonus uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> on-time-bonus u0) err-invalid-amount)
    (asserts! (< dispute-penalty-val 0) err-invalid-amount)
    (asserts! (> success-bonus u0) err-invalid-amount)
    
    (var-set on-time-delivery-bonus on-time-bonus)
    (var-set dispute-penalty dispute-penalty-val)
    (var-set successful-escrow-bonus success-bonus)
    
    (ok true)
  )
)

(define-read-only (get-supplier-reputation (supplier principal))
  (map-get? supplier-reputation supplier)
)

(define-read-only (get-supplier-tier (supplier principal))
  (default-to 
    { tier: u0, tier-name: "Bronze", unlocked-at: u0 }
    (map-get? supplier-tier supplier)
  )
)

(define-read-only (get-reputation-history (supplier principal) (escrow-id uint))
  (map-get? reputation-history { supplier: supplier, escrow-id: escrow-id })
)

(define-read-only (calculate-reliability-score (supplier principal))
  (match (map-get? supplier-reputation supplier)
    reputation
      (let
        (
          (total (get total-escrows reputation))
          (successful (get successful-escrows reputation))
        )
        (if (> total u0)
          (some (/ (* successful u100) total))
          (some u0)
        )
      )
    none
  )
)

(define-read-only (get-reputation-parameters)
  {
    on-time-bonus: (var-get on-time-delivery-bonus),
    dispute-penalty: (var-get dispute-penalty),
    success-bonus: (var-get successful-escrow-bonus)
  }
)

(define-public (create-milestone-based-escrow 
  (supplier principal) 
  (description (string-ascii 500)) 
  (delivery-days uint)
  (milestones (list 10 { description: (string-ascii 200), payment-percentage: uint })))
  (let
    (
      (escrow-id (+ (var-get escrow-counter) u1))
      (amount (stx-get-balance tx-sender))
      (current-height burn-block-height)
      (deadline (+ current-height (* delivery-days u144)))
      (total-percentage (fold sum-percentages milestones u0))
    )
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (> delivery-days u0) err-invalid-amount)
    (asserts! (not (is-eq tx-sender supplier)) err-unauthorized)
    (asserts! (> (len milestones) u0) err-invalid-milestone-count)
    (asserts! (is-eq total-percentage u100) err-invalid-amount)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (map-set escrows escrow-id {
      buyer: tx-sender,
      supplier: supplier,
      amount: amount,
      description: description,
      status: "active",
      created-at: current-height,
      delivery-deadline: deadline,
      delivery-confirmed-at: none,
      cancelled-at: none
    })
    
    (map-set escrow-balances escrow-id amount)
    
    (map-set user-escrows tx-sender 
      (unwrap! (as-max-len? 
        (append (default-to (list) (map-get? user-escrows tx-sender)) escrow-id) 
        u100) 
        err-invalid-amount))
    
    (map-set user-escrows supplier
      (unwrap! (as-max-len? 
        (append (default-to (list) (map-get? user-escrows supplier)) escrow-id) 
        u100) 
        err-invalid-amount))
    
    (map-set escrow-milestones escrow-id
      (create-milestone-list milestones u0))
    
    (if (is-none (map-get? supplier-reputation supplier))
      (map-set supplier-reputation supplier 
        {
          total-escrows: u0,
          successful-escrows: u0,
          disputed-escrows: u0,
          on-time-deliveries: u0,
          total-volume: u0,
          reputation-score: 0,
          last-updated: burn-block-height
        })
      true)
    
    (var-set escrow-counter escrow-id)
    (ok escrow-id)
  )
)

(define-public (complete-milestone (escrow-id uint) (milestone-id uint))
  (let
    (
      (escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found))
      (milestones (unwrap! (map-get? escrow-milestones escrow-id) err-milestone-not-found))
      (escrow-balance (unwrap! (map-get? escrow-balances escrow-id) err-not-found))
      (milestone (unwrap! (element-at milestones milestone-id) err-milestone-not-found))
      (current-height burn-block-height)
      (payment-amount (/ (* (get amount escrow-data) (get payment-percentage milestone)) u100))
    )
    (asserts! (is-eq tx-sender (get buyer escrow-data)) err-unauthorized)
    (asserts! (is-eq (get status escrow-data) "active") err-invalid-status)
    (asserts! (not (get completed milestone)) err-milestone-already-completed)
    (asserts! (<= payment-amount escrow-balance) err-insufficient-funds)
    
    (try! (as-contract (stx-transfer? payment-amount tx-sender (get supplier escrow-data))))
    
    (map-set escrow-milestones escrow-id
      (unwrap! (as-max-len?
        (map update-milestone-status 
          milestones
          (list 
            { target-id: milestone-id, current-id: u0, current-height: current-height }
            { target-id: milestone-id, current-id: u1, current-height: current-height }
            { target-id: milestone-id, current-id: u2, current-height: current-height }
            { target-id: milestone-id, current-id: u3, current-height: current-height }
            { target-id: milestone-id, current-id: u4, current-height: current-height }
            { target-id: milestone-id, current-id: u5, current-height: current-height }
            { target-id: milestone-id, current-id: u6, current-height: current-height }
            { target-id: milestone-id, current-id: u7, current-height: current-height }
            { target-id: milestone-id, current-id: u8, current-height: current-height }
            { target-id: milestone-id, current-id: u9, current-height: current-height }))
        u10)
        err-milestone-not-found))
    
    (map-set escrow-balances escrow-id (- escrow-balance payment-amount))
    
    (if (all-milestones-completed escrow-id)
      (begin
        (map-set escrows escrow-id (merge escrow-data { status: "completed" }))
        (try! (update-supplier-reputation (get supplier escrow-data) escrow-id "success"))
        (ok payment-amount))
      (ok payment-amount))
  )
)

(define-read-only (get-escrow-milestones (escrow-id uint))
  (map-get? escrow-milestones escrow-id)
)

(define-read-only (get-milestone-progress (escrow-id uint))
  (match (map-get? escrow-milestones escrow-id)
    milestones
      (let
        (
          (total-milestones (len milestones))
          (completed-count (fold count-completed-milestones milestones u0))
        )
        (some {
          total: total-milestones,
          completed: completed-count,
          percentage: (if (> total-milestones u0) (/ (* completed-count u100) total-milestones) u0)
        })
      )
    none
  )
)

(define-private (sum-percentages (milestone { description: (string-ascii 200), payment-percentage: uint }) (total uint))
  (+ total (get payment-percentage milestone))
)

(define-private (create-milestone-list (milestones (list 10 { description: (string-ascii 200), payment-percentage: uint })) (counter uint))
  (map create-milestone-item 
    milestones
    (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9))
)

(define-private (create-milestone-item 
  (milestone { description: (string-ascii 200), payment-percentage: uint })
  (id uint))
  {
    milestone-id: id,
    description: (get description milestone),
    payment-percentage: (get payment-percentage milestone),
    completed: false,
    completed-at: none
  }
)

(define-private (update-milestone-status 
  (milestone { milestone-id: uint, description: (string-ascii 200), payment-percentage: uint, completed: bool, completed-at: (optional uint) })
  (context { target-id: uint, current-id: uint, current-height: uint }))
  (if (is-eq (get milestone-id milestone) (get target-id context))
    (merge milestone { 
      completed: true, 
      completed-at: (some (get current-height context)) 
    })
    milestone
  )
)

(define-private (count-completed-milestones 
  (milestone { milestone-id: uint, description: (string-ascii 200), payment-percentage: uint, completed: bool, completed-at: (optional uint) })
  (count uint))
  (if (get completed milestone)
    (+ count u1)
    count
  )
)

(define-private (all-milestones-completed (escrow-id uint))
  (match (map-get? escrow-milestones escrow-id)
    milestones
      (let
        (
          (total (len milestones))
          (completed (fold count-completed-milestones milestones u0))
        )
        (is-eq total completed)
      )
    false
  )
)

(define-public (raise-dispute (escrow-id uint) (reason (string-ascii 500)) (evidence (string-ascii 500)))
  (let
    (
      (escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found))
      (dispute-id (+ (var-get dispute-counter) u1))
      (current-height burn-block-height)
      (is-buyer (is-eq tx-sender (get buyer escrow-data)))
      (is-supplier (is-eq tx-sender (get supplier escrow-data)))
    )
    (asserts! (or is-buyer is-supplier) err-unauthorized)
    (asserts! (is-eq (get status escrow-data) "active") err-invalid-status)
    (asserts! (is-none (map-get? dispute-by-escrow escrow-id)) err-dispute-already-exists)
    
    (map-set escrow-disputes dispute-id {
      dispute-id: dispute-id,
      escrow-id: escrow-id,
      initiator: tx-sender,
      reason: reason,
      buyer-evidence: (if is-buyer evidence ""),
      supplier-evidence: (if is-supplier evidence ""),
      status: "pending",
      resolution: "",
      buyer-refund-percentage: u0,
      created-at: current-height,
      resolved-at: none,
      resolved-by: none
    })
    
    (map-set dispute-by-escrow escrow-id dispute-id)
    
    (map-set escrows escrow-id (merge escrow-data { status: "disputed" }))
    
    (var-set dispute-counter dispute-id)
    (ok dispute-id)
  )
)

(define-public (submit-dispute-evidence (escrow-id uint) (evidence (string-ascii 500)))
  (let
    (
      (escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found))
      (dispute-id (unwrap! (map-get? dispute-by-escrow escrow-id) err-dispute-not-found))
      (dispute-data (unwrap! (map-get? escrow-disputes dispute-id) err-dispute-not-found))
      (is-buyer (is-eq tx-sender (get buyer escrow-data)))
      (is-supplier (is-eq tx-sender (get supplier escrow-data)))
    )
    (asserts! (or is-buyer is-supplier) err-unauthorized)
    (asserts! (is-eq (get status dispute-data) "pending") err-dispute-already-resolved)
    
    (map-set escrow-disputes dispute-id 
      (merge dispute-data {
        buyer-evidence: (if is-buyer evidence (get buyer-evidence dispute-data)),
        supplier-evidence: (if is-supplier evidence (get supplier-evidence dispute-data))
      }))
    
    (ok true)
  )
)

(define-public (resolve-dispute-with-split (escrow-id uint) (buyer-refund-percentage uint))
  (let
    (
      (escrow-data (unwrap! (map-get? escrows escrow-id) err-not-found))
      (dispute-id (unwrap! (map-get? dispute-by-escrow escrow-id) err-dispute-not-found))
      (dispute-data (unwrap! (map-get? escrow-disputes dispute-id) err-dispute-not-found))
      (escrow-balance (unwrap! (map-get? escrow-balances escrow-id) err-not-found))
      (current-height burn-block-height)
      (buyer-amount (/ (* escrow-balance buyer-refund-percentage) u100))
      (supplier-amount (- escrow-balance buyer-amount))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-eq (get status dispute-data) "pending") err-dispute-already-resolved)
    (asserts! (<= buyer-refund-percentage u100) err-invalid-resolution)
    (asserts! (> escrow-balance u0) err-insufficient-funds)
    
    (if (> buyer-amount u0)
      (try! (as-contract (stx-transfer? buyer-amount tx-sender (get buyer escrow-data))))
      true)
    
    (if (> supplier-amount u0)
      (try! (as-contract (stx-transfer? supplier-amount tx-sender (get supplier escrow-data))))
      true)
    
    (map-set escrow-disputes dispute-id 
      (merge dispute-data {
        status: "resolved",
        resolution: (if (is-eq buyer-refund-percentage u100) "buyer-favor" 
                     (if (is-eq buyer-refund-percentage u0) "supplier-favor" "split")),
        buyer-refund-percentage: buyer-refund-percentage,
        resolved-at: (some current-height),
        resolved-by: (some tx-sender)
      }))
    
    (map-set escrows escrow-id (merge escrow-data { status: "resolved" }))
    (map-set escrow-balances escrow-id u0)
    
    (try! (update-supplier-reputation (get supplier escrow-data) escrow-id "dispute"))
    
    (ok { buyer-refund: buyer-amount, supplier-payment: supplier-amount })
  )
)

(define-read-only (get-dispute (dispute-id uint))
  (map-get? escrow-disputes dispute-id)
)

(define-read-only (get-dispute-by-escrow (escrow-id uint))
  (match (map-get? dispute-by-escrow escrow-id)
    dispute-id (map-get? escrow-disputes dispute-id)
    none
  )
)

(define-read-only (get-dispute-counter)
  (var-get dispute-counter)
)
