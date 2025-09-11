;; IP Creation Attribution Engine
;; Tracks creative lineage, inspiration sources, and collaborative contributions

;; Attribution timeline for tracking creation milestones
(define-map attribution-timeline
  { ip-id: uint, milestone-id: uint }
  {
    creator: principal,
    milestone-type: (string-ascii 30),
    description: (string-utf8 200),
    timestamp: uint,
    process-hash: (buff 32),
    work-percentage: uint,
    verification-signature: (buff 65)
  }
)

;; Attribution sources for tracking inspiration and references
(define-map attribution-sources
  { ip-id: uint, source-id: uint }
  {
    source-type: (string-ascii 20),
    source-ip-id: (optional uint),
    external-reference: (string-utf8 300),
    influence-weight: uint,
    attribution-note: (string-utf8 200),
    added-by: principal,
    added-at: uint
  }
)

;; Collaborative contributions for multi-creator works
(define-map collaborative-contributions
  { ip-id: uint, contributor: principal }
  {
    contribution-type: (string-ascii 30),
    contribution-weight: uint,
    start-timestamp: uint,
    end-timestamp: uint,
    contribution-hash: (buff 32),
    verified-by-creator: bool,
    contribution-description: (string-utf8 200)
  }
)

;; Attribution disputes
(define-map attribution-disputes
  { dispute-id: uint }
  {
    disputed-ip-id: uint,
    disputer: principal,
    dispute-type: (string-ascii 30),
    evidence-hash: (buff 32),
    dispute-description: (string-utf8 300),
    status: (string-ascii 20),
    filed-at: uint,
    resolved-at: uint
  }
)

;; Data variables
(define-data-var next-milestone-id uint u1)
(define-data-var next-source-id uint u1)
(define-data-var next-attribution-dispute-id uint u1)

;; Error constants
(define-constant err-not-found (err u201))
(define-constant err-unauthorized (err u202))
(define-constant err-invalid-input (err u203))
(define-constant err-invalid-percentage (err u205))
(define-constant err-already-exists (err u206))
(define-constant err-expired (err u207))

;; Global data variables
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


(define-map marketplace-listings
  { listing-id: uint }
  {
    ip-id: uint,
    seller: principal,
    price: uint,
    listing-type: (string-ascii 20),
    duration: uint,
    created-at: uint,
    expires-at: uint,
    status: (string-ascii 20),
    terms: (string-utf8 300)
  }
)

(define-map marketplace-offers
  { listing-id: uint, buyer: principal }
  {
    offer-price: uint,
    offered-at: uint,
    expires-at: uint,
    status: (string-ascii 20)
  }
)

(define-data-var listing-counter uint u1)

(define-constant err-listing-not-found (err u106))
(define-constant err-listing-expired (err u107))
(define-constant err-insufficient-payment (err u108))
(define-constant err-invalid-listing-type (err u109))
(define-constant err-cannot-buy-own-listing (err u110))

(define-public (create-marketplace-listing 
    (ip-id uint) 
    (price uint) 
    (listing-type (string-ascii 20))
    (duration uint)
    (terms (string-utf8 300)))
  (let
    (
      (listing-id (var-get listing-counter))
      (ip-details (unwrap! (get-ip-details ip-id) err-not-found))
      (current-time stacks-block-height)
      (expiration-time (+ current-time duration))
    )
    (asserts! (is-eq tx-sender (get creator ip-details)) err-unauthorized)
    (asserts! (> price u0) err-invalid-input)
    (asserts! (or (is-eq listing-type "sale") (is-eq listing-type "license")) err-invalid-listing-type)
    (asserts! (> duration u0) err-invalid-input)
    
    (map-set marketplace-listings
      { listing-id: listing-id }
      {
        ip-id: ip-id,
        seller: tx-sender,
        price: price,
        listing-type: listing-type,
        duration: duration,
        created-at: current-time,
        expires-at: expiration-time,
        status: "active",
        terms: terms
      }
    )
    
    (var-set listing-counter (+ listing-id u1))
    (ok listing-id)
  )
)

(define-public (make-offer (listing-id uint) (offer-price uint) (offer-duration uint))
  (let
    (
      (listing (unwrap! (map-get? marketplace-listings { listing-id: listing-id }) err-listing-not-found))
      (current-time stacks-block-height)
      (offer-expiry (+ current-time offer-duration))
    )
    (asserts! (is-eq (get status listing) "active") err-listing-expired)
    (asserts! (< current-time (get expires-at listing)) err-listing-expired)
    (asserts! (not (is-eq tx-sender (get seller listing))) err-cannot-buy-own-listing)
    (asserts! (> offer-price u0) err-invalid-input)
    
    (map-set marketplace-offers
      { listing-id: listing-id, buyer: tx-sender }
      {
        offer-price: offer-price,
        offered-at: current-time,
        expires-at: offer-expiry,
        status: "pending"
      }
    )
    (ok true)
  )
)

(define-public (accept-offer (listing-id uint) (buyer principal))
  (let
    (
      (listing (unwrap! (map-get? marketplace-listings { listing-id: listing-id }) err-listing-not-found))
      (offer (unwrap! (map-get? marketplace-offers { listing-id: listing-id, buyer: buyer }) err-not-found))
      (ip-details (unwrap! (get-ip-details (get ip-id listing)) err-not-found))
      (current-time stacks-block-height)
    )
    (asserts! (is-eq tx-sender (get seller listing)) err-unauthorized)
    (asserts! (is-eq (get status offer) "pending") err-invalid-input)
    (asserts! (< current-time (get expires-at offer)) err-listing-expired)
    
    (if (is-eq (get listing-type listing) "sale")
      (begin
        (try! (nft-transfer? intellectual-property (get ip-id listing) tx-sender buyer))
        (map-set ip-registry
          { id: (get ip-id listing) }
          (merge ip-details { creator: buyer })
        )
      )
      (map-set ip-license-grants
        { ip-id: (get ip-id listing), licensee: buyer }
        {
          granted-at: current-time,
          expires-at: (+ current-time (get duration listing)),
          terms: (get terms listing),
          payment: (get offer-price offer)
        }
      )
    )
    
    (try! (distribute-marketplace-payment (get ip-id listing) (get offer-price offer)))
    
    (map-set marketplace-listings
      { listing-id: listing-id }
      (merge listing { status: "sold" })
    )
    
    (map-set marketplace-offers
      { listing-id: listing-id, buyer: buyer }
      (merge offer { status: "accepted" })
    )
    
    (ok true)
  )
)

(define-public (buy-now (listing-id uint))
  (let
    (
      (listing (unwrap! (map-get? marketplace-listings { listing-id: listing-id }) err-listing-not-found))
      (ip-details (unwrap! (get-ip-details (get ip-id listing)) err-not-found))
      (current-time stacks-block-height)
    )
    (asserts! (is-eq (get status listing) "active") err-listing-expired)
    (asserts! (< current-time (get expires-at listing)) err-listing-expired)
    (asserts! (not (is-eq tx-sender (get seller listing))) err-cannot-buy-own-listing)
    
    (if (is-eq (get listing-type listing) "sale")
      (begin
        (try! (nft-transfer? intellectual-property (get ip-id listing) (get seller listing) tx-sender))
        (map-set ip-registry
          { id: (get ip-id listing) }
          (merge ip-details { creator: tx-sender })
        )
      )
      (map-set ip-license-grants
        { ip-id: (get ip-id listing), licensee: tx-sender }
        {
          granted-at: current-time,
          expires-at: (+ current-time (get duration listing)),
          terms: (get terms listing),
          payment: (get price listing)
        }
      )
    )
    
    (try! (distribute-marketplace-payment (get ip-id listing) (get price listing)))
    
    (map-set marketplace-listings
      { listing-id: listing-id }
      (merge listing { status: "sold" })
    )
    
    (ok true)
  )
)

(define-private (distribute-marketplace-payment (ip-id uint) (payment-amount uint))
  (let
    (
      (ip-details (unwrap! (get-ip-details ip-id) err-not-found))
      (royalty-percent (get royalty-percent ip-details))
      (royalty-amount (/ (* payment-amount royalty-percent) u100))
      (seller-amount (- payment-amount royalty-amount))
    )
    ;; (if (> royalty-amount u0)
    ;;   ;; (try! (distribute-royalty-to-shareholders ip-id royalty-amount))
    ;;   (ok true)
    ;; )
    (ok true)
  )
)

(define-private (distribute-royalty-to-shareholders (ip-id uint) (royalty-amount uint))
  (match (map-get? revenue-sharing { ip-id: ip-id })
    sharing-info 
      (let
        (
          (total-shares (get total-shares sharing-info))
        )
        (ok true)
      )
    (ok true)
  )
)

(define-public (cancel-listing (listing-id uint))
  (let
    (
      (listing (unwrap! (map-get? marketplace-listings { listing-id: listing-id }) err-listing-not-found))
    )
    (asserts! (is-eq tx-sender (get seller listing)) err-unauthorized)
    (asserts! (is-eq (get status listing) "active") err-invalid-input)
    
    (map-set marketplace-listings
      { listing-id: listing-id }
      (merge listing { status: "cancelled" })
    )
    (ok true)
  )
)

(define-public (withdraw-offer (listing-id uint))
  (let
    (
      (offer (unwrap! (map-get? marketplace-offers { listing-id: listing-id, buyer: tx-sender }) err-not-found))
    )
    (asserts! (is-eq (get status offer) "pending") err-invalid-input)
    
    (map-set marketplace-offers
      { listing-id: listing-id, buyer: tx-sender }
      (merge offer { status: "withdrawn" })
    )
    (ok true)
  )
)

(define-read-only (get-marketplace-listing (listing-id uint))
  (match (map-get? marketplace-listings { listing-id: listing-id })
    listing (ok listing)
    err-listing-not-found
  )
)

(define-read-only (get-marketplace-offer (listing-id uint) (buyer principal))
  (match (map-get? marketplace-offers { listing-id: listing-id, buyer: buyer })
    offer (ok offer)
    err-not-found
  )
)

(define-read-only (get-listing-counter)
  (ok (var-get listing-counter))
)(define-map verification-registry
  { ip-id: uint }
  {
    proof-hash: (buff 32),
    verification-timestamp: uint,
    verification-method: (string-ascii 50),
    cryptographic-signature: (buff 65),
    witness-count: uint,
    verification-status: (string-ascii 20),
    metadata-uri: (string-ascii 200)
  }
)

(define-map verification-witnesses
  { ip-id: uint, witness: principal }
  {
    witness-signature: (buff 65),
    witness-timestamp: uint,
    witness-statement: (string-utf8 200)
  }
)

(define-map verification-chain
  { ip-id: uint, chain-id: uint }
  {
    previous-hash: (buff 32),
    current-hash: (buff 32),
    timestamp: uint,
    action: (string-ascii 50),
    actor: principal
  }
)

(define-data-var verification-chain-counter uint u1)

(define-constant err-verification-exists (err u111))
(define-constant err-verification-failed (err u112))
(define-constant err-insufficient-witnesses (err u113))
(define-constant err-invalid-signature (err u114))

(define-public (create-verification-proof 
    (ip-id uint) 
    (proof-hash (buff 32))
    (verification-method (string-ascii 50))
    (cryptographic-signature (buff 65))
    (metadata-uri (string-ascii 200)))
  (let
    (
      (ip-details (unwrap! (get-ip-details ip-id) err-not-found))
      (existing-verification (map-get? verification-registry { ip-id: ip-id }))
      (verification-chain-id (var-get verification-chain-counter))
    )
    (asserts! (is-eq tx-sender (get creator ip-details)) err-unauthorized)
    (asserts! (is-none existing-verification) err-verification-exists)
    (asserts! (> (len verification-method) u0) err-invalid-input)
    (asserts! (> (len metadata-uri) u0) err-invalid-input)
    
    (map-set verification-registry
      { ip-id: ip-id }
      {
        proof-hash: proof-hash,
        verification-timestamp: stacks-block-height,
        verification-method: verification-method,
        cryptographic-signature: cryptographic-signature,
        witness-count: u0,
        verification-status: "pending",
        metadata-uri: metadata-uri
      }
    )
    
    (map-set verification-chain
      { ip-id: ip-id, chain-id: verification-chain-id }
      {
        previous-hash: 0x0000000000000000000000000000000000000000000000000000000000000000,
        current-hash: proof-hash,
        timestamp: stacks-block-height,
        action: "verification_created",
        actor: tx-sender
      }
    )
    
    (var-set verification-chain-counter (+ verification-chain-id u1))
    (ok true)
  )
)

(define-public (add-verification-witness 
    (ip-id uint) 
    (witness-signature (buff 65))
    (witness-statement (string-utf8 200)))
  (let
    (
      (verification (unwrap! (map-get? verification-registry { ip-id: ip-id }) err-not-found))
      (existing-witness (map-get? verification-witnesses { ip-id: ip-id, witness: tx-sender }))
      (verification-chain-id (var-get verification-chain-counter))
    )
    (asserts! (is-none existing-witness) err-already-exists)
    (asserts! (is-eq (get verification-status verification) "pending") err-invalid-input)
    (asserts! (> (len witness-statement) u0) err-invalid-input)
    
    (map-set verification-witnesses
      { ip-id: ip-id, witness: tx-sender }
      {
        witness-signature: witness-signature,
        witness-timestamp: stacks-block-height,
        witness-statement: witness-statement
      }
    )
    
    (let
      (
        (new-witness-count (+ (get witness-count verification) u1))
        (current-hash (hash160 witness-signature))
      )
      (map-set verification-registry
        { ip-id: ip-id }
        (merge verification { witness-count: new-witness-count })
      )
      
      (map-set verification-chain
        { ip-id: ip-id, chain-id: verification-chain-id }
        {
          previous-hash: (get proof-hash verification),
          current-hash: current-hash,
          timestamp: stacks-block-height,
          action: "witness_added",
          actor: tx-sender
        }
      )
      
      (var-set verification-chain-counter (+ verification-chain-id u1))
      (ok true)
    )
  )
)

(define-public (finalize-verification (ip-id uint))
  (let
    (
      (verification (unwrap! (map-get? verification-registry { ip-id: ip-id }) err-not-found))
      (ip-details (unwrap! (get-ip-details ip-id) err-not-found))
      (verification-chain-id (var-get verification-chain-counter))
    )
    (asserts! (is-eq tx-sender (get creator ip-details)) err-unauthorized)
    (asserts! (is-eq (get verification-status verification) "pending") err-invalid-input)
    (asserts! (>= (get witness-count verification) u2) err-insufficient-witnesses)
    
    (let
      (
        (final-hash (hash160 (get proof-hash verification)))
      )
      (map-set verification-registry
        { ip-id: ip-id }
        (merge verification { verification-status: "verified" })
      )
      
      (map-set verification-chain
        { ip-id: ip-id, chain-id: verification-chain-id }
        {
          previous-hash: (get proof-hash verification),
          current-hash: final-hash,
          timestamp: stacks-block-height,
          action: "verification_finalized",
          actor: tx-sender
        }
      )
      
      (var-set verification-chain-counter (+ verification-chain-id u1))
      (ok true)
    )
  )
)

(define-public (challenge-verification (ip-id uint) (challenge-evidence (buff 32)) (challenge-reason (string-utf8 300)))
  (let
    (
      (verification (unwrap! (map-get? verification-registry { ip-id: ip-id }) err-not-found))
      (verification-chain-id (var-get verification-chain-counter))
    )
    (asserts! (is-eq (get verification-status verification) "verified") err-invalid-input)
    (asserts! (> (len challenge-reason) u0) err-invalid-input)
    
    (map-set verification-registry
      { ip-id: ip-id }
      (merge verification { verification-status: "challenged" })
    )
    
    (map-set verification-chain
      { ip-id: ip-id, chain-id: verification-chain-id }
      {
        previous-hash: (get proof-hash verification),
        current-hash: challenge-evidence,
        timestamp: stacks-block-height,
        action: "verification_challenged",
        actor: tx-sender
      }
    )
    
    (var-set verification-chain-counter (+ verification-chain-id u1))
    (ok true)
  )
)

(define-public (validate-verification-chain (ip-id uint) (verification-chain-id uint))
  (let
    (
      (verification (unwrap! (map-get? verification-registry { ip-id: ip-id }) err-not-found))
      (chain-entry (map-get? verification-chain { ip-id: ip-id, chain-id: verification-chain-id }))
    )
    (asserts! (> verification-chain-id u0) err-invalid-input)
    
    (ok (is-some chain-entry))
  )
)

(define-read-only (get-verification-details (ip-id uint))
  (match (map-get? verification-registry { ip-id: ip-id })
    verification (ok verification)
    err-not-found
  )
)

(define-read-only (get-verification-witness (ip-id uint) (witness principal))
  (match (map-get? verification-witnesses { ip-id: ip-id, witness: witness })
    witness-data (ok witness-data)
    err-not-found
  )
)

(define-read-only (get-verification-chain-entry (ip-id uint) (verification-chain-id uint))
  (match (map-get? verification-chain { ip-id: ip-id, chain-id: verification-chain-id })
    chain-entry (ok chain-entry)
    err-not-found
  )
)

(define-read-only (is-verification-valid (ip-id uint))
  (match (map-get? verification-registry { ip-id: ip-id })
    verification 
      (ok (and 
        (is-eq (get verification-status verification) "verified")
        (>= (get witness-count verification) u2)))
    (ok false)
  )
)

;; Dynamic Pricing Intelligence Engine
;; Tracks market performance and adjusts IP pricing based on demand, usage patterns, and creator preferences

(define-map ip-pricing-intelligence
  { ip-id: uint }
  {
    base-price: uint,
    current-price: uint,
    price-multiplier: uint, ;; stored as percentage (100 = 1.0x, 150 = 1.5x)
    min-price: uint,
    max-price: uint,
    surge-threshold: uint, ;; number of licenses needed to trigger surge pricing
    decay-rate: uint, ;; price reduction rate when demand drops (percentage per block)
    last-price-update: uint,
    creator-locked: bool, ;; if true, creator has locked pricing parameters
    pricing-strategy: (string-ascii 20) ;; "demand", "time", "performance", "manual"
  }
)

(define-map ip-market-metrics
  { ip-id: uint }
  {
    total-licenses: uint,
    licenses-last-100-blocks: uint,
    total-revenue: uint,
    revenue-last-100-blocks: uint,
    view-count: uint,
    engagement-score: uint, ;; calculated based on views, licenses, and interactions
    peak-demand-price: uint,
    average-license-price: uint,
    last-license-timestamp: uint,
    trending-score: uint ;; algorithm-based trending calculation
  }
)

(define-map pricing-history
  { ip-id: uint, block-height: uint }
  {
    price: uint,
    trigger-reason: (string-ascii 30), ;; "surge", "decay", "manual", "strategy"
    demand-level: uint, ;; 1-10 scale
    licenses-in-period: uint
  }
)

(define-map global-market-stats
  { category: (string-ascii 50) }
  {
    average-price: uint,
    total-volume: uint,
    active-ips: uint,
    trending-multiplier: uint ;; category-wide pricing influence
  }
)

;; New error constants for pricing engine
(define-constant err-pricing-locked (err u115))
(define-constant err-invalid-price-range (err u116))
(define-constant err-invalid-strategy (err u117))
(define-constant err-price-calculation-failed (err u118))

;; Initialize pricing intelligence for an IP
(define-public (setup-pricing-intelligence 
    (ip-id uint) 
    (base-price uint)
    (min-price uint)
    (max-price uint)
    (surge-threshold uint)
    (decay-rate uint)
    (pricing-strategy (string-ascii 20)))
  (let
    (
      (ip-details (unwrap! (get-ip-details ip-id) err-not-found))
    )
    ;; Verify IP owner
    (asserts! (is-eq tx-sender (get creator ip-details)) err-unauthorized)
    ;; Validate price range
    (asserts! (<= min-price base-price) err-invalid-price-range)
    (asserts! (<= base-price max-price) err-invalid-price-range)
    ;; Validate strategy
    (asserts! (or (is-eq pricing-strategy "demand") 
                  (or (is-eq pricing-strategy "time") 
                      (or (is-eq pricing-strategy "performance") 
                          (is-eq pricing-strategy "manual")))) err-invalid-strategy)
    
    ;; Initialize pricing intelligence
    (map-set ip-pricing-intelligence
      { ip-id: ip-id }
      {
        base-price: base-price,
        current-price: base-price,
        price-multiplier: u100, ;; start at 1.0x
        min-price: min-price,
        max-price: max-price,
        surge-threshold: surge-threshold,
        decay-rate: decay-rate,
        last-price-update: stacks-block-height,
        creator-locked: false,
        pricing-strategy: pricing-strategy
      }
    )
    
    ;; Initialize market metrics
    (map-set ip-market-metrics
      { ip-id: ip-id }
      {
        total-licenses: u0,
        licenses-last-100-blocks: u0,
        total-revenue: u0,
        revenue-last-100-blocks: u0,
        view-count: u0,
        engagement-score: u0,
        peak-demand-price: base-price,
        average-license-price: base-price,
        last-license-timestamp: u0,
        trending-score: u0
      }
    )
    
    (ok true)
  )
)

;; Record IP interaction (view, license attempt, etc.)
(define-public (record-ip-interaction (ip-id uint) (interaction-type (string-ascii 20)) (value uint))
  (let
    (
      (existing-metrics (unwrap! (map-get? ip-market-metrics { ip-id: ip-id }) err-not-found))
      (current-time stacks-block-height)
    )
    ;; Update metrics based on interaction type
    (if (is-eq interaction-type "view")
      ;; Handle view interaction
      (begin
        (map-set ip-market-metrics
          { ip-id: ip-id }
          (merge existing-metrics { 
            view-count: (+ (get view-count existing-metrics) u1),
            engagement-score: (calculate-engagement-score ip-id (+ (get view-count existing-metrics) u1) (get total-licenses existing-metrics))
          })
        )
        (ok true)
      )
      ;; Handle license interaction
      (if (is-eq interaction-type "license")
        (let
          (
            (new-total-licenses (+ (get total-licenses existing-metrics) u1))
            (new-total-revenue (+ (get total-revenue existing-metrics) value))
            (recent-licenses (count-recent-licenses ip-id current-time))
          )
          (map-set ip-market-metrics
            { ip-id: ip-id }
            (merge existing-metrics {
              total-licenses: new-total-licenses,
              licenses-last-100-blocks: recent-licenses,
              total-revenue: new-total-revenue,
              revenue-last-100-blocks: (calculate-recent-revenue ip-id current-time),
              last-license-timestamp: current-time,
              average-license-price: (/ new-total-revenue new-total-licenses),
              engagement-score: (calculate-engagement-score ip-id (get view-count existing-metrics) new-total-licenses)
            })
          )
          ;; Trigger price recalculation for demand-based pricing
          (update-dynamic-pricing ip-id)
        )
        (ok true) ;; Unknown interaction type, ignore
      )
    )
  )
)

;; Calculate dynamic pricing based on current market conditions
(define-public (update-dynamic-pricing (ip-id uint))
  (let
    (
      (pricing-intel (unwrap! (map-get? ip-pricing-intelligence { ip-id: ip-id }) err-not-found))
      (market-metrics (unwrap! (map-get? ip-market-metrics { ip-id: ip-id }) err-not-found))
      (current-time stacks-block-height)
      (blocks-since-update (- current-time (get last-price-update pricing-intel)))
    )
    ;; Skip if pricing is manually locked by creator
    (asserts! (not (get creator-locked pricing-intel)) err-pricing-locked)
    
    ;; Calculate new price based on strategy
    (let
      (
        (new-price (if (is-eq (get pricing-strategy pricing-intel) "demand")
                     (calculate-demand-price ip-id pricing-intel market-metrics)
                     (if (is-eq (get pricing-strategy pricing-intel) "performance")
                       (calculate-performance-price ip-id pricing-intel market-metrics)
                       (if (is-eq (get pricing-strategy pricing-intel) "time")
                         (calculate-time-based-price ip-id pricing-intel blocks-since-update)
                         (get current-price pricing-intel) ;; manual strategy, no auto-update
                       )
                     )
                   ))
        (clamped-price (clamp-price new-price pricing-intel))
        (new-multiplier (/ (* clamped-price u100) (get base-price pricing-intel)))
      )
      ;; Update pricing intelligence
      (map-set ip-pricing-intelligence
        { ip-id: ip-id }
        (merge pricing-intel {
          current-price: clamped-price,
          price-multiplier: new-multiplier,
          last-price-update: current-time
        })
      )
      
      ;; Record price change in history
      (map-set pricing-history
        { ip-id: ip-id, block-height: current-time }
        {
          price: clamped-price,
          trigger-reason: (get pricing-strategy pricing-intel),
          demand-level: (calculate-demand-level market-metrics),
          licenses-in-period: (get licenses-last-100-blocks market-metrics)
        }
      )
      
      ;; Update peak price if necessary
      (if (> clamped-price (get peak-demand-price market-metrics))
        (begin
          (map-set ip-market-metrics
            { ip-id: ip-id }
            (merge market-metrics { peak-demand-price: clamped-price })
          )
          (ok true)
        )
        (ok true)
      )
    )
  )
)

;; Calculate demand-based pricing using surge and decay algorithms
(define-private (calculate-demand-price (ip-id uint) (pricing-intel (tuple (base-price uint) (current-price uint) (price-multiplier uint) (min-price uint) (max-price uint) (surge-threshold uint) (decay-rate uint) (last-price-update uint) (creator-locked bool) (pricing-strategy (string-ascii 20)))) (metrics (tuple (total-licenses uint) (licenses-last-100-blocks uint) (total-revenue uint) (revenue-last-100-blocks uint) (view-count uint) (engagement-score uint) (peak-demand-price uint) (average-license-price uint) (last-license-timestamp uint) (trending-score uint))))
  (let
    (
      (recent-licenses (get licenses-last-100-blocks metrics))
      (surge-threshold (get surge-threshold pricing-intel))
      (current-price (get current-price pricing-intel))
      (base-price (get base-price pricing-intel))
    )
    ;; Apply surge pricing if recent demand exceeds threshold
    (if (>= recent-licenses surge-threshold)
      ;; Surge pricing: increase by 25% for every threshold exceeded
      (let
        (
          (surge-multiplier (+ u100 (* u25 (/ recent-licenses surge-threshold))))
        )
        (/ (* base-price surge-multiplier) u100)
      )
      ;; Decay pricing: gradually reduce price when demand is low
      (if (is-eq recent-licenses u0)
        (let
          (
            (decay-amount (/ (* current-price (get decay-rate pricing-intel)) u100))
          )
          (if (> current-price (+ base-price decay-amount))
            (- current-price decay-amount)
            base-price ;; Don't go below base price
          )
        )
        current-price ;; Maintain current price for moderate demand
      )
    )
  )
)

;; Calculate performance-based pricing using engagement and revenue metrics
(define-private (calculate-performance-price (ip-id uint) (pricing-intel (tuple (base-price uint) (current-price uint) (price-multiplier uint) (min-price uint) (max-price uint) (surge-threshold uint) (decay-rate uint) (last-price-update uint) (creator-locked bool) (pricing-strategy (string-ascii 20)))) (metrics (tuple (total-licenses uint) (licenses-last-100-blocks uint) (total-revenue uint) (revenue-last-100-blocks uint) (view-count uint) (engagement-score uint) (peak-demand-price uint) (average-license-price uint) (last-license-timestamp uint) (trending-score uint))))
  (let
    (
      (engagement-score (get engagement-score metrics))
      (base-price (get base-price pricing-intel))
      (performance-multiplier (if (> engagement-score u50)
                               (+ u100 (* (- engagement-score u50) u2)) ;; +2% per point above 50
                               (if (< engagement-score u25)
                                 (- u100 (* (- u25 engagement-score) u1)) ;; -1% per point below 25
                                 u100 ;; neutral performance, maintain base price
                               )
                             ))
    )
    (/ (* base-price performance-multiplier) u100)
  )
)

;; Calculate time-based pricing with gradual decay
(define-private (calculate-time-based-price (ip-id uint) (pricing-intel (tuple (base-price uint) (current-price uint) (price-multiplier uint) (min-price uint) (max-price uint) (surge-threshold uint) (decay-rate uint) (last-price-update uint) (creator-locked bool) (pricing-strategy (string-ascii 20)))) (blocks-elapsed uint))
  (let
    (
      (current-price (get current-price pricing-intel))
      (decay-rate (get decay-rate pricing-intel))
      (base-price (get base-price pricing-intel))
      ;; Apply time decay every 100 blocks
      (decay-periods (/ blocks-elapsed u100))
      (total-decay (/ (* current-price (* decay-rate decay-periods)) u100))
    )
    (if (> current-price (+ base-price total-decay))
      (- current-price total-decay)
      base-price
    )
  )
)

;; Utility function to clamp price within min/max bounds
(define-private (clamp-price (price uint) (pricing-intel (tuple (base-price uint) (current-price uint) (price-multiplier uint) (min-price uint) (max-price uint) (surge-threshold uint) (decay-rate uint) (last-price-update uint) (creator-locked bool) (pricing-strategy (string-ascii 20)))))
  (let
    (
      (min-price (get min-price pricing-intel))
      (max-price (get max-price pricing-intel))
    )
    (if (< price min-price)
      min-price
      (if (> price max-price)
        max-price
        price
      )
    )
  )
)

;; Calculate engagement score based on views and licenses
(define-private (calculate-engagement-score (ip-id uint) (views uint) (licenses uint))
  (if (is-eq views u0)
    u0
    (let
      (
        (conversion-rate (/ (* licenses u100) views)) ;; percentage of views that convert to licenses
        (base-score (* conversion-rate u10)) ;; scale up the score
      )
      (if (> base-score u100) u100 base-score) ;; cap at 100
    )
  )
)

;; Calculate demand level (1-10 scale) for historical tracking
(define-private (calculate-demand-level (metrics (tuple (total-licenses uint) (licenses-last-100-blocks uint) (total-revenue uint) (revenue-last-100-blocks uint) (view-count uint) (engagement-score uint) (peak-demand-price uint) (average-license-price uint) (last-license-timestamp uint) (trending-score uint))))
  (let
    (
      (recent-licenses (get licenses-last-100-blocks metrics))
    )
    (if (>= recent-licenses u20) u10      ;; Very high demand
      (if (>= recent-licenses u15) u9
        (if (>= recent-licenses u10) u8
          (if (>= recent-licenses u7) u7
            (if (>= recent-licenses u5) u6
              (if (>= recent-licenses u3) u5
                (if (>= recent-licenses u2) u4
                  (if (>= recent-licenses u1) u3
                    (if (> (get view-count metrics) u10) u2
                      u1 ;; Low demand
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  )
)

;; Count recent licenses in the last 100 blocks (simplified for demo)
(define-private (count-recent-licenses (ip-id uint) (current-time uint))
  ;; In a real implementation, this would iterate through recent transactions
  ;; For this demo, we'll use the stored value and increment
  (match (map-get? ip-market-metrics { ip-id: ip-id })
    metrics (+ (get licenses-last-100-blocks metrics) u1)
    u1
  )
)

;; Calculate recent revenue (simplified for demo)
(define-private (calculate-recent-revenue (ip-id uint) (current-time uint))
  ;; Similar to count-recent-licenses, this would calculate actual recent revenue
  (match (map-get? ip-market-metrics { ip-id: ip-id })
    metrics (get revenue-last-100-blocks metrics)
    u0
  )
)

;; Allow creators to lock/unlock automatic pricing
(define-public (toggle-pricing-lock (ip-id uint))
  (let
    (
      (ip-details (unwrap! (get-ip-details ip-id) err-not-found))
      (pricing-intel (unwrap! (map-get? ip-pricing-intelligence { ip-id: ip-id }) err-not-found))
    )
    (asserts! (is-eq tx-sender (get creator ip-details)) err-unauthorized)
    
    (map-set ip-pricing-intelligence
      { ip-id: ip-id }
      (merge pricing-intel { creator-locked: (not (get creator-locked pricing-intel)) })
    )
    (ok true)
  )
)

;; Get current dynamic pricing information
(define-read-only (get-pricing-intelligence (ip-id uint))
  (match (map-get? ip-pricing-intelligence { ip-id: ip-id })
    pricing-intel (ok pricing-intel)
    err-not-found
  )
)

;; Get market performance metrics
(define-read-only (get-market-metrics (ip-id uint))
  (match (map-get? ip-market-metrics { ip-id: ip-id })
    metrics (ok metrics)
    err-not-found
  )
)

;; Get pricing history for a specific block
(define-read-only (get-pricing-history (ip-id uint) (target-block uint))
  (match (map-get? pricing-history { ip-id: ip-id, block-height: target-block })
    history (ok history)
    err-not-found
  )
)

;; IP Creation Attribution Functions

;; Simplified IP creation attribution map from the summary
(define-map ip-creation-attribution
  { ip-id: uint }
  {
    milestones: (list 50 { timestamp: uint, description: (string-utf8 200), evidence-hash: (buff 32) }),
    inspiration-sources: (list 20 uint),  ;; list of other IP ids inspired by
    contributors: (list 20 { contributor: principal, contribution: (string-utf8 100) })
  }
)

;; Adds a creation milestone to an IP
(define-public (add-creation-milestone (ip-id uint) (timestamp uint) (description (string-utf8 200)) (evidence-hash (buff 32)))
  (let (
    (ip-details (unwrap! (get-ip-details ip-id) err-not-found))
    (attr (default-to {
      milestones: (list),
      inspiration-sources: (list),
      contributors: (list)
    } (map-get? ip-creation-attribution { ip-id: ip-id })))
  )
    (asserts! (is-eq tx-sender (get creator ip-details)) err-unauthorized)
    (asserts! (> (len description) u0) err-invalid-input)

    (map-set ip-creation-attribution
      { ip-id: ip-id }
      {
        milestones: (unwrap! (as-max-len? (append (get milestones attr) { timestamp: timestamp, description: description, evidence-hash: evidence-hash }) u50) (err u500)),
        inspiration-sources: (get inspiration-sources attr),
        contributors: (get contributors attr)
      }
    )
    (ok true)
  )
)

;; Link inspiration sources - other IP ids that inspired this IP
(define-public (add-inspiration-source (ip-id uint) (source-ip-id uint))
  (let (
    (ip-details (unwrap! (get-ip-details ip-id) err-not-found))
    (source-exists (map-get? ip-registry { id: source-ip-id }))
    (attr (default-to {
      milestones: (list),
      inspiration-sources: (list),
      contributors: (list)
    } (map-get? ip-creation-attribution { ip-id: ip-id })))
  )

    (asserts! (is-eq tx-sender (get creator ip-details)) err-unauthorized)
    (asserts! (is-some source-exists) err-not-found)

    ;; Avoid duplicates
    (let (
      (sources (get inspiration-sources attr))
      (already-linked (is-some (index-of sources source-ip-id)))
    )
      (asserts! (not already-linked) err-invalid-input)

      (map-set ip-creation-attribution
        { ip-id: ip-id }
        {
          milestones: (get milestones attr),
          inspiration-sources: (unwrap! (as-max-len? (append sources source-ip-id) u20) (err u500)),
          contributors: (get contributors attr)
        }
      )
      (ok true)
    )
  )
)



;; Read-only function to get the creation attribution details of an IP
(define-read-only (get-creation-attribution (ip-id uint))
  (match (map-get? ip-creation-attribution { ip-id: ip-id })
    attr (ok attr)
    err-not-found
  )
)

;; Missing constant definitions and NFT definition
(define-non-fungible-token intellectual-property uint)
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))

