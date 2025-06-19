;; StacksFlow Options Protocol
;; Decentralized Options Trading Platform for Bitcoin Layer 2
;;
;; Built for the Stacks blockchain ecosystem, StacksFlow enables trustless creation,
;; trading, and settlement of Bitcoin-backed options contracts. This protocol leverages
;; Stacks' unique ability to interact with Bitcoin for secure, decentralized derivatives
;; trading with transparent pricing and automated settlement.
;;
;; Features:
;; - Native Bitcoin integration through Stacks Layer 2
;; - Trustless option creation and exercise
;; - Multi-collateral support with SIP-010 token standard
;; - Oracle-based price feeds for accurate settlement
;; - Automated collateral management and risk controls
;; - Decentralized governance and fee structures

;; TRAIT DEFINITIONS

;; Standard SIP-010 fungible token trait for collateral management
(define-trait sip-010-trait (
  (transfer
    (uint principal principal (optional (buff 34)))
    (response bool uint)
  )
  (get-balance
    (principal)
    (response uint uint)
  )
  (get-total-supply
    ()
    (response uint uint)
  )
  (get-decimals
    ()
    (response uint uint)
  )
  (get-token-uri
    ()
    (response (optional (string-utf8 256)) uint)
  )
  (get-name
    ()
    (response (string-ascii 32) uint)
  )
  (get-symbol
    ()
    (response (string-ascii 32) uint)
  )
))

;; ERROR CONSTANTS

(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INSUFFICIENT-BALANCE (err u1001))
(define-constant ERR-INVALID-EXPIRY (err u1002))
(define-constant ERR-INVALID-STRIKE-PRICE (err u1003))
(define-constant ERR-OPTION-NOT-FOUND (err u1004))
(define-constant ERR-OPTION-EXPIRED (err u1005))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u1006))
(define-constant ERR-ALREADY-EXERCISED (err u1007))
(define-constant ERR-INVALID-PREMIUM (err u1008))
(define-constant ERR-INVALID-TOKEN (err u1009))
(define-constant ERR-INVALID-SYMBOL (err u1010))
(define-constant ERR-INVALID-TIMESTAMP (err u1011))
(define-constant ERR-INVALID-ADDRESS (err u1012))
(define-constant ERR-ZERO-ADDRESS (err u1013))
(define-constant ERR-EMPTY-SYMBOL (err u1014))

;; DATA STRUCTURES

;; Core option contract data structure
(define-map options
  uint
  {
    writer: principal, ;; Option writer (seller)
    holder: (optional principal), ;; Option holder (buyer)
    collateral-amount: uint, ;; Locked collateral amount
    strike-price: uint, ;; Exercise price in base units
    premium: uint, ;; Option premium cost
    expiry: uint, ;; Expiration block height
    is-exercised: bool, ;; Exercise status
    option-type: (string-ascii 4), ;; "CALL" or "PUT"
    state: (string-ascii 9), ;; "ACTIVE" or "EXERCISED"
  }
)

;; User position tracking for portfolio management
(define-map user-positions
  principal
  {
    written-options: (list 10 uint), ;; Options user has written
    held-options: (list 10 uint), ;; Options user holds
    total-collateral-locked: uint, ;; Total locked collateral
  }
)

;; Whitelisted tokens approved for collateral use
(define-map approved-tokens
  principal
  bool
)

;; Price oracle data for settlement calculations
(define-map price-feeds
  (string-ascii 10)
  {
    price: uint, ;; Current price in base units
    timestamp: uint, ;; Last update timestamp
    source: principal, ;; Oracle source address
  }
)

;; Allowed trading pairs and symbols
(define-map allowed-symbols
  (string-ascii 10)
  bool
)

;; STATE VARIABLES

;; Unique identifier counter for new options
(define-data-var next-option-id uint u1)

;; Protocol governance and fee management
(define-data-var contract-owner principal tx-sender)
(define-data-var protocol-fee-rate uint u100) ;; 1% = 100 basis points

;; UTILITY FUNCTIONS

;; Returns the minimum of two values
(define-private (get-min
    (a uint)
    (b uint)
  )
  (if (< a b)
    a
    b
  )
)

;; Validates principal address for security
(define-private (is-valid-principal (address principal))
  (and
    (not (is-eq address (as-contract tx-sender))) ;; Can't be the contract itself
    (not (is-eq address .base)) ;; Can't be base contract
    (not (is-eq address tx-sender)) ;; Can't be the owner
    true
  )
)

;; Validates symbol string format
(define-private (is-valid-symbol (symbol (string-ascii 10)))
  (and
    (not (is-eq symbol "")) ;; Can't be empty
    (not (is-eq symbol " ")) ;; Can't be just whitespace
    (>= (len symbol) u2) ;; Must be at least 2 characters
  )
)

;; Checks if token is approved for use as collateral
(define-private (is-approved-token (token principal))
  (default-to false (map-get? approved-tokens token))
)

;; Checks if price feed symbol is allowed
(define-private (is-allowed-symbol (symbol (string-ascii 10)))
  (default-to false (map-get? allowed-symbols symbol))
)

;; Checks if token is critical to platform operation
(define-private (is-critical-token (token principal))
  (or
    (is-eq token .wrapped-btc)
    (is-eq token .wrapped-stx)
  )
)

;; Checks if symbol is critical to platform operation
(define-private (is-critical-symbol (symbol (string-ascii 10)))
  (or
    (is-eq symbol "BTC-USD")
    (is-eq symbol "STX-USD")
  )
)

;; CORE OPTION MECHANICS

;; Validates collateral requirements based on option type and market conditions
(define-private (check-collateral-requirement
    (amount uint)
    (strike uint)
    (option-type (string-ascii 4))
  )
  (if (is-eq option-type "CALL")
    (>= amount strike)
    (>= amount (/ (* strike u100000000) (get-current-price)))
  )
)

;; Retrieves current market price from oracle
(define-private (get-current-price)
  (get price (unwrap! (map-get? price-feeds "BTC-USD") u0))
)

;; Helper function to extract option ID from option data
(define-private (get-option-id (option {
  writer: principal,
  holder: (optional principal),
  collateral-amount: uint,
  strike-price: uint,
  premium: uint,
  expiry: uint,
  is-exercised: bool,
  option-type: (string-ascii 4),
  state: (string-ascii 9),
}))
  (var-get next-option-id)
)

;; OPTION EXERCISE LOGIC

;; Processes exercise of CALL options with profit calculation
(define-private (exercise-call
    (token <sip-010-trait>)
    (option {
      writer: principal,
      holder: (optional principal),
      collateral-amount: uint,
      strike-price: uint,
      premium: uint,
      expiry: uint,
      is-exercised: bool,
      option-type: (string-ascii 4),
      state: (string-ascii 9),
    })
    (current-price uint)
  )
  (let (
      (profit (- current-price (get strike-price option)))
      (payout (get-min profit (get collateral-amount option)))
    )
    ;; Transfer payout to option holder
    (try! (as-contract (contract-call? token transfer payout tx-sender
      (unwrap! (get holder option) ERR-NOT-AUTHORIZED) none
    )))
    ;; Return remaining collateral to option writer
    (try! (as-contract (contract-call? token transfer (- (get collateral-amount option) payout)
      tx-sender (get writer option) none
    )))
    ;; Update option state to exercised
    (map-set options (get-option-id option)
      (merge option {
        is-exercised: true,
        state: "EXERCISED",
      })
    )
    (ok true)
  )
)

;; Processes exercise of PUT options with profit calculation
(define-private (exercise-put
    (token <sip-010-trait>)
    (option {
      writer: principal,
      holder: (optional principal),
      collateral-amount: uint,
      strike-price: uint,
      premium: uint,
      expiry: uint,
      is-exercised: bool,
      option-type: (string-ascii 4),
      state: (string-ascii 9),
    })
    (current-price uint)
  )
  (let (
      (profit (- (get strike-price option) current-price))
      (payout (get-min profit (get collateral-amount option)))
    )
    ;; Transfer payout to option holder
    (try! (as-contract (contract-call? token transfer payout tx-sender
      (unwrap! (get holder option) ERR-NOT-AUTHORIZED) none
    )))
    ;; Return remaining collateral to option writer
    (try! (as-contract (contract-call? token transfer (- (get collateral-amount option) payout)
      tx-sender (get writer option) none
    )))
    ;; Update option state to exercised
    (map-set options (get-option-id option)
      (merge option {
        is-exercised: true,
        state: "EXERCISED",
      })
    )
    (ok true)
  )
)

;; PUBLIC FUNCTIONS - OPTION TRADING

;; Creates a new option contract with specified parameters
;; Writers lock collateral and set terms for potential buyers
(define-public (write-option
    (token <sip-010-trait>)
    (collateral-amount uint)
    (strike-price uint)
    (premium uint)
    (expiry uint)
    (option-type (string-ascii 4))
  )
  (let (
      (option-id (var-get next-option-id))
      (current-time stacks-block-height)
      (token-principal (contract-of token))
    )
    ;; Comprehensive validation of option parameters
    (asserts! (is-approved-token token-principal) ERR-INVALID-TOKEN)
    (asserts! (> expiry current-time) ERR-INVALID-EXPIRY)
    (asserts! (> strike-price u0) ERR-INVALID-STRIKE-PRICE)
    (asserts! (> premium u0) ERR-INVALID-PREMIUM)
    (asserts!
      (check-collateral-requirement collateral-amount strike-price option-type)
      ERR-INSUFFICIENT-COLLATERAL
    )
    ;; Lock collateral from option writer
    (try! (contract-call? token transfer collateral-amount tx-sender
      (as-contract tx-sender) none
    ))
    ;; Create new option entry
    (map-set options option-id {
      writer: tx-sender,
      holder: none,
      collateral-amount: collateral-amount,
      strike-price: strike-price,
      premium: premium,
      expiry: expiry,
      is-exercised: false,
      option-type: option-type,
      state: "ACTIVE",
    })
    ;; Update writer's position tracking
    (let ((current-position (default-to {
        written-options: (list),
        held-options: (list),
        total-collateral-locked: u0,
      }
        (map-get? user-positions tx-sender)
      )))
      (map-set user-positions tx-sender
        (merge current-position {
          written-options: (unwrap-panic (as-max-len? (append (get written-options current-position) option-id)
            u10
          )),
          total-collateral-locked: (+ (get total-collateral-locked current-position) collateral-amount),
        })
      )
    )
    ;; Increment option ID counter for next option
    (var-set next-option-id (+ option-id u1))
    (ok option-id)
  )
)