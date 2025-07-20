# PresaleContract
Smart contract used to do the 1XMM presale --> participants shall review the code to understand what the smart contract is doing.<br/>

# How it works
A limited amount of 1XMM tokens will be transferred to the pre-sale smart contract.<br/>
The pre-sale smart contract will automatically manage transfers of 1XMM tokens to participants. A pre-defined list of "_Payment Tokens_" are authorized:<br/>
- On Ethereum: ETH, WETH, USDT, USDC, DAI
- On TON Network: TON, USDT, USDC
More authorized tokens can be added in time.
<br/>
**Note**: the TON payments are not active yet

## Process
Participants must be **whitelisted to participate to the pre-sale**. Once a participant is whitelisted, he will be added to the authorized users and will be allowed to purchase 1XMM tokens. Several steps are covered during the process:
1. Participants will be asked to provide an allowance to the pre-sale smart contract, equal to the amount of Payment Tokens which is intended to be transferred
2. Pre-sale smart contract will execute the transfer of 1XMM based on the specified exchange price --> exchange price will be disclosed before validation of the transaction
3. If participants provide too many Payment Tokens (i.e. if there is not enough 1XMM tokens available), **all extra Payment Tokens are reverted back** to participants

## Exchange Price
The exchange price shows the number of 1XMM tokens provided for 1 Payment Token.<br/>
The exchange prices can be adjusted in time --> participants shall always check the pre-sale price before validating a transaction.

## Pre-Sale Period
The pre-sale is active only for a given period of time. No transaction can be executed outside the pre-sale period.<br/>
When the amount of 1XMM tokens reaches 0, the pre-sale will automatically end.