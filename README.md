# Tokenized Intellectual Property Registry

A decentralized registry for protecting intellectual property rights on the Stacks blockchain.

## Overview

This smart contract provides a system for creators to register, manage, and monetize their intellectual property in a decentralized manner. The contract implements a non-fungible token (NFT) system where each token represents a unique piece of intellectual property.

## Features

- Register intellectual property with detailed metadata
- Add collaborators with different permission levels
- Grant and revoke licenses to other users
- Transfer ownership of intellectual property
- Update intellectual property details
- Extend the duration of intellectual property protection
- Track ownership history and licensing

## Contract Functions

### Registration

```clarity
(register-intellectual-property 
  (title (string-ascii 100))
  (description (string-utf8 500))
  (category (string-ascii 50))
  (content-hash (buff 32))
  (royalty-percent uint)
  (duration uint))
```

### Collaboration Management

```clarity
(add-collaborator (ip-id uint) (collaborator principal) (permission-level (string-ascii 20)))
(remove-collaborator (ip-id uint) (collaborator principal))
```

### Licensing

```clarity
(grant-license (ip-id uint) (licensee principal) (terms (string-utf8 500)) (duration uint) (payment uint))
(revoke-license (ip-id uint) (licensee principal))
```

### Ownership

```clarity
(transfer-ownership (ip-id uint) (new-owner principal) (price uint))
```

### Metadata Management

```clarity
(update-ip-details 
  (ip-id uint) 
  (title (string-ascii 100))
  (description (string-utf8 500))
  (category (string-ascii 50))
  (content-hash (buff 32))
  (royalty-percent uint))
(extend-ip-duration (ip-id uint) (additional-duration uint))
```

### Read-Only Functions

```clarity
(get-ip-details (id uint))
(get-ip-collaborators (id uint))
(get-ip-licenses (id uint))
(get-last-id)
(is-owner (id uint))
(is-collaborator (id uint) (user principal))
```

## Usage Example

1. Register a new intellectual property:

```clarity
(contract-call? .intellectual-p register-intellectual-property "My Novel" "A story about blockchain" "Literature" 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef u5 u52560)
```

2. Add a collaborator:

```clarity
(contract-call? .intellectual-p add-collaborator u1 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM "edit")
```

3. Grant a license:

```clarity
(contract-call? .intellectual-p grant-license u1 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM "Commercial use allowed with attribution" u26280 u1000)
```

4. Transfer ownership:

```clarity
(contract-call? .intellectual-p transfer-ownership u1 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM u50000)
```

## Deployment

Deploy this contract using Clarinet:

```bash
clarinet contract publish