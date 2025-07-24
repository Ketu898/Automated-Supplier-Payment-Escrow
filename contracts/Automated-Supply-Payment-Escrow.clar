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

(define-data-var escrow-counter uint u0)

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
