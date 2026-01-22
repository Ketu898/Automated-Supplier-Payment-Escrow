# 🔐 Automated Supplier Payment Escrow

A secure Clarity smart contract that automates supplier payments through an escrow system, ensuring payment is only released after confirmed delivery.

## 🌟 Features

- ✅ **Secure Escrow**: Funds are locked until delivery confirmation
- 🚚 **Delivery Tracking**: Buyers confirm delivery before payment release
- ⏰ **Deadline Management**: Automatic escrow expiration with refund capability
- 🔄 **Dispute Resolution**: Built-in dispute mechanism with owner arbitration
- 📊 **User Dashboard**: Track all escrows by user
- 🔧 **Flexible Deadlines**: Extend delivery deadlines when needed

## 🚀 Quick Start

### Prerequisites
- [Clarinet](https://github.com/hirosystems/clarinet) installed
- STX tokens for testing

### Installation
```bash
git clone <repository-url>
cd Automated-Supplier-Payment-Escrow
clarinet check
```

## 📋 Contract Functions

### 🛍️ Creating an Escrow
```clarity
(contract-call? .Automated-Supply-Payment-Escrow create-escrow
  'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7  ;; supplier address
  "Web development services"                      ;; description
  u30)                                           ;; delivery days
```

### ✅ Confirming Delivery
```clarity
(contract-call? .Automated-Supply-Payment-Escrow confirm-delivery
  u1                           ;; escrow ID
  "Delivered on time")         ;; confirmation notes
```

### 💰 Releasing Payment
```clarity
(contract-call? .Automated-Supply-Payment-Escrow release-payment u1)  ;; escrow ID
```

### ❌ Canceling Escrow (After Deadline)
```clarity
(contract-call? .Automated-Supply-Payment-Escrow cancel-escrow u1)  ;; escrow ID
```

## 🔍 Read-Only Functions

### Get Escrow Details
```clarity
(contract-call? .Automated-Supply-Payment-Escrow get-escrow u1)
```

### Check User's Escrows
```clarity
(contract-call? .Automated-Supply-Payment-Escrow get-user-escrows 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
```

### Check Time Remaining
```clarity
(contract-call? .Automated-Supply-Payment-Escrow calculate-time-remaining u1)
```

## 📊 Escrow States

| State | Description |
|-------|-------------|
| `active` | 🟢 Escrow created, awaiting delivery |
| `delivered` | 📦 Delivery confirmed by buyer |
| `completed` | ✅ Payment released to supplier |
| `cancelled` | ❌ Escrow cancelled, funds returned to buyer |
| `disputed` | ⚠️ Dispute raised, awaiting resolution |
| `resolved` | 🔧 Dispute resolved by contract owner |

## 🔄 Workflow

1. **Buyer Creates Escrow** 🛍️
   - Funds are locked in contract
   - Delivery deadline is set
   - Supplier is notified

2. **Supplier Delivers** 🚚
   - Goods/services provided to buyer
   - Buyer reviews delivery

3. **Buyer Confirms** ✅
   - Buyer confirms satisfactory delivery
   - Escrow status changes to "delivered"

4. **Payment Released** 💰
   - Anyone can trigger payment release
   - Funds transferred to supplier
   - Escrow marked as "completed"

## ⚠️ Error Codes

- `u100`: Owner-only function
- `u101`: Escrow not found
- `u102`: Insufficient funds
- `u103`: Unauthorized access
- `u104`: Invalid escrow status
- `u105`: Delivery not confirmed
- `u106`: Escrow expired
- `u107`: Escrow already exists
- `u108`: Invalid amount
- `u109`: Cannot cancel escrow

## 🛡️ Security Features

- **Access Control**: Only authorized users can perform specific actions
- **Deadline Enforcement**: Automatic expiration prevents indefinite locks
- **Dispute Resolution**: Owner can resolve disputes fairly
- **Balance Tracking**: Accurate fund management with safety checks

## 🧪 Testing

Run the test suite:
```bash
clarinet test
```

## 🔧 Development

Check contract syntax:
```bash
clarinet check
```

Deploy to testnet:
```bash
clarinet deploy --testnet
```

## 📝 License

This project is open source and available under the MIT License.

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

---

Built with ❤️ using Clarity and Stacks blockchain technology
