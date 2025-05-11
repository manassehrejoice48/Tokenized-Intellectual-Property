
;; title: intellectual-p




(define-non-fungible-token intellectual-property uint)

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-expired (err u104))
(define-constant err-invalid-input (err u105))

(define-data-var next-id uint u1)

(define-map ip-registry
  { id: uint }
  {
    title: (string-ascii 100),
    description: (string-utf8 500),
    creator: principal,
    created-at: uint,
    expires-at: uint,
    category: (string-ascii 50),
    status: (string-ascii 20),
    hash: (buff 32),
    royalty-percent: uint
  }
)

(define-map ip-collaborators
  { ip-id: uint, collaborator: principal }
  { permission-level: (string-ascii 20) }
)

(define-map ip-license-grants
  { ip-id: uint, licensee: principal }
  {
    granted-at: uint,
    expires-at: uint,
    terms: (string-utf8 500),
    payment: uint
  }
)

(define-map ip-transfer-history
  { ip-id: uint, tx-id: uint }
  {
    from: principal,
    to: principal,
    timestamp: uint,
    price: uint
  }
)

(define-data-var transfer-tx-id uint u1)

(define-read-only (get-ip-details (id uint))
  (match (map-get? ip-registry { id: id })
    entry (ok entry)
    err-not-found
  )
)

(define-read-only (get-ip-collaborators (id uint))
  (ok (map-get? ip-collaborators { ip-id: id, collaborator: tx-sender }))
)

(define-read-only (get-ip-licenses (id uint))
  (ok (map-get? ip-license-grants { ip-id: id, licensee: tx-sender }))
)

(define-read-only (get-last-id)
  (ok (var-get next-id))
)

(define-read-only (is-owner (id uint))
  (match (map-get? ip-registry { id: id })
    entry (ok (is-eq (get creator entry) tx-sender))
    err-not-found
  )
)

(define-read-only (is-collaborator (id uint) (user principal))
  (match (map-get? ip-collaborators { ip-id: id, collaborator: user })
    entry (ok true)
    (ok false)
  )
)

(define-public (register-intellectual-property 
    (title (string-ascii 100))
    (description (string-utf8 500))
    (category (string-ascii 50))
    (content-hash (buff 32))
    (royalty-percent uint)
    (duration uint))
  (let
    (
      (new-id (var-get next-id))
      (current-time stacks-block-height)
      (expiration-time (+ stacks-block-height duration))
    )
    (asserts! (< royalty-percent u100) err-invalid-input)
    (asserts! (> (len title) u0) err-invalid-input)
    (asserts! (> (len description) u0) err-invalid-input)
    (asserts! (> (len category) u0) err-invalid-input)
    
    (try! (nft-mint? intellectual-property new-id tx-sender))
    
    (map-set ip-registry
      { id: new-id }
      {
        title: title,
        description: description,
        creator: tx-sender,
        created-at: current-time,
        expires-at: expiration-time,
        category: category,
        status: "active",
        hash: content-hash,
        royalty-percent: royalty-percent
      }
    )
    
    (var-set next-id (+ new-id u1))
    (ok new-id)
  )
)

(define-public (add-collaborator (ip-id uint) (collaborator principal) (permission-level (string-ascii 20)))
  (let
    (
      (ip-details (unwrap! (get-ip-details ip-id) err-not-found))
    )
    (asserts! (is-eq tx-sender (get creator ip-details)) err-unauthorized)
    (asserts! (or (is-eq permission-level "read") (is-eq permission-level "edit") (is-eq permission-level "admin")) err-invalid-input)
    
    (map-set ip-collaborators
      { ip-id: ip-id, collaborator: collaborator }
      { permission-level: permission-level }
    )
    (ok true)
  )
)

(define-public (remove-collaborator (ip-id uint) (collaborator principal))
  (let
    (
      (ip-details (unwrap! (get-ip-details ip-id) err-not-found))
    )
    (asserts! (is-eq tx-sender (get creator ip-details)) err-unauthorized)
    (map-delete ip-collaborators { ip-id: ip-id, collaborator: collaborator })
    (ok true)
  )
)

(define-public (grant-license (ip-id uint) (licensee principal) (terms (string-utf8 500)) (duration uint) (payment uint))
  (let
    (
      (ip-details (unwrap! (get-ip-details ip-id) err-not-found))
      (current-time stacks-block-height)
      (expiration-time (+ current-time duration))
    )
    (asserts! (is-eq tx-sender (get creator ip-details)) err-unauthorized)
    
    (map-set ip-license-grants
      { ip-id: ip-id, licensee: licensee }
      {
        granted-at: current-time,
        expires-at: expiration-time,
        terms: terms,
        payment: payment
      }
    )
    (ok true)
  )
)

(define-public (revoke-license (ip-id uint) (licensee principal))
  (let
    (
      (ip-details (unwrap! (get-ip-details ip-id) err-not-found))
    )
    (asserts! (is-eq tx-sender (get creator ip-details)) err-unauthorized)
    (map-delete ip-license-grants { ip-id: ip-id, licensee: licensee })
    (ok true)
  )
)

(define-public (transfer-ownership (ip-id uint) (new-owner principal) (price uint))
  (let
    (
      (ip-details (unwrap! (get-ip-details ip-id) err-not-found))
      (current-tx-id (var-get transfer-tx-id))
    )
    (asserts! (is-eq tx-sender (get creator ip-details)) err-unauthorized)
    
    (try! (nft-transfer? intellectual-property ip-id tx-sender new-owner))
    
    (map-set ip-registry
      { id: ip-id }
      (merge ip-details { creator: new-owner })
    )
    
    (map-set ip-transfer-history
      { ip-id: ip-id, tx-id: current-tx-id }
      {
        from: tx-sender,
        to: new-owner,
        timestamp: stacks-block-height,
        price: price
      }
    )
    
    (var-set transfer-tx-id (+ current-tx-id u1))
    (ok true)
  )
)

(define-public (update-ip-details 
    (ip-id uint) 
    (title (string-ascii 100))
    (description (string-utf8 500))
    (category (string-ascii 50))
    (content-hash (buff 32))
    (royalty-percent uint))
  (let
    (
      (ip-details (unwrap! (get-ip-details ip-id) err-not-found))
    )
    (asserts! (is-eq tx-sender (get creator ip-details)) err-unauthorized)
    (asserts! (< royalty-percent u100) err-invalid-input)
    
    (map-set ip-registry
      { id: ip-id }
      (merge ip-details {
        title: title,
        description: description,
        category: category,
        hash: content-hash,
        royalty-percent: royalty-percent
      })
    )
    (ok true)
  )
)

(define-public (extend-ip-duration (ip-id uint) (additional-duration uint))
  (let
    (
      (ip-details (unwrap! (get-ip-details ip-id) err-not-found))
      (current-expiry (get expires-at ip-details))
    )
    (asserts! (is-eq tx-sender (get creator ip-details)) err-unauthorized)
    
    (map-set ip-registry
      { id: ip-id }
      (merge ip-details {
        expires-at: (+ current-expiry additional-duration)
      })
    )
    (ok true)
  )
)


(define-map dispute-registry
  { dispute-id: uint, ip-id: uint }
  {
    complainant: principal,
    reason: (string-utf8 500),
    evidence-hash: (buff 32),
    status: (string-ascii 20),
    filed-at: uint,
    resolved-at: uint,
    resolution: (string-utf8 500),
    arbitrator: principal
  }
)

(define-data-var dispute-counter uint u1)

(define-map arbitrators
  { address: principal }
  { active: bool }
)

(define-public (register-arbitrator (arbitrator principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set arbitrators
      { address: arbitrator }
      { active: true }
    )
    (ok true)))

(define-public (file-dispute (ip-id uint) (reason (string-utf8 500)) (evidence-hash (buff 32)))
  (let
    ((dispute-id (var-get dispute-counter)))
    (map-set dispute-registry
      { dispute-id: dispute-id, ip-id: ip-id }
      {
        complainant: tx-sender,
        reason: reason,
        evidence-hash: evidence-hash,
        status: "pending",
        filed-at: stacks-block-height,
        resolved-at: u0,
        resolution: u"",
        arbitrator: contract-owner
      }
    )
    (var-set dispute-counter (+ dispute-id u1))
    (ok dispute-id)))

(define-public (resolve-dispute (dispute-id uint) (ip-id uint) (resolution (string-utf8 500)))
  (let
    ((dispute (unwrap! (map-get? dispute-registry { dispute-id: dispute-id, ip-id: ip-id }) err-not-found))
     (is-arbitrator (unwrap! (map-get? arbitrators { address: tx-sender }) err-unauthorized)))
    (asserts! (get active is-arbitrator) err-unauthorized)
    (map-set dispute-registry
      { dispute-id: dispute-id, ip-id: ip-id }
      (merge dispute {
        status: "resolved",
        resolved-at: stacks-block-height,
        resolution: resolution,
        arbitrator: tx-sender
      })
    )
    (ok true)))

  


(define-map revenue-sharing
  { ip-id: uint }
  {
    total-shares: uint,
    remaining-shares: uint
  }
)

(define-map share-holders
  { ip-id: uint, holder: principal }
  {
    shares: uint,
    earnings: uint
  }
)

(define-public (setup-revenue-sharing (ip-id uint) (total-shares uint))
  (let
    ((ip-details (unwrap! (get-ip-details ip-id) err-not-found)))
    (asserts! (is-eq tx-sender (get creator ip-details)) err-unauthorized)
    (asserts! (>= total-shares u100) err-invalid-input)
    (map-set revenue-sharing
      { ip-id: ip-id }
      {
        total-shares: total-shares,
        remaining-shares: total-shares
      }
    )
    (ok true)))

(define-public (allocate-shares (ip-id uint) (recipient principal) (share-amount uint))
  (let
    ((ip-details (unwrap! (get-ip-details ip-id) err-not-found))
     (sharing-info (unwrap! (map-get? revenue-sharing { ip-id: ip-id }) err-not-found)))
    (asserts! (is-eq tx-sender (get creator ip-details)) err-unauthorized)
    (asserts! (<= share-amount (get remaining-shares sharing-info)) err-invalid-input)
    (map-set revenue-sharing
      { ip-id: ip-id }
      { 
        total-shares: (get total-shares sharing-info),
        remaining-shares: (- (get remaining-shares sharing-info) share-amount)
      }
    )
    (map-set share-holders
      { ip-id: ip-id, holder: recipient }
      {
        shares: share-amount,
        earnings: u0
      }
    )
    (ok true)))

(define-public (distribute-revenue (ip-id uint) (amount uint))
  (let
    ((ip-details (unwrap! (get-ip-details ip-id) err-not-found))
     (sharing-info (unwrap! (map-get? revenue-sharing { ip-id: ip-id }) err-not-found)))
    (asserts! (is-eq tx-sender (get creator ip-details)) err-unauthorized)
    (ok true)))