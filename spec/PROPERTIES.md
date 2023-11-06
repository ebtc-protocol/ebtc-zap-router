# Properties

List of properties of the eBTC ZapRouter, following the categorization by [Certora](https://github.com/Certora/Tutorials/blob/master/06.Lesson_ThinkingProperties/Categorizing_Properties.pdf):

- Valid States
- State Transitions
- Variable Transitions
- High-Level Properties
- Unit Tests

## EbtcZapRouter

| Property | Description | Category | Tested |
| --- | --- | --- | --- |
| ZR-01 | The balances of tracked tokens in the ZapRouter should never change after a valid user operation | High Level | |
| ZR-02 | The balance of ETH in the ZapRouter should never change after creation | High Level | |
| ZR-03 | The ZapRouter should never be the borrower of a Cdp | High Level | |
| ZR-04 | The ZapRouter should always renounce positionManagerApproval during a valid user operation | High Level | |
