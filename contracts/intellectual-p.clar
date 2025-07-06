
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
