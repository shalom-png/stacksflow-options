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