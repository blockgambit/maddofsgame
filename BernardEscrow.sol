pragma solidity 0.5.8;

import "./token/BernardsCutToken.sol";
import "./SafeMath.sol";


contract BernardEscrow {
  using SafeMath for uint256;

  BernardsCutToken public token;

  uint256 public constant CALCULATION_DISABLED_BLOCKS = 21600; //  used to avoid spam
  
  uint256 public prevCalculationBlock;
  uint256 public tokenFractionProfitCalculatedTimes;
  uint256 public ongoingBernardFee;

  mapping (uint256 => uint256) public tokenFractionProfitForCalculatedIdx;
  mapping (address => uint256) public profitWithdrawnOnCalculationIdx;

  event BernardFeeWithdrawn(address by, uint256 amount);

  //  MODIFIERS
  modifier onlyCalculationEnabled() {
    require(block.number.sub(prevCalculationBlock) >= CALCULATION_DISABLED_BLOCKS, "Calculation disabled");
    _;
  }

  modifier onlyTokenHolder() {
    require(token.balanceOf(msg.sender) > 0, "Not token holder");
    _;
  }

  modifier onlyToken() {
    require(msg.sender == address(token), "Not BCT");
    _;
  }

  /**
   * @dev Constructor.
   * @param _token Token address.
   * TESTED
   */
  constructor (address _token) public {
    token = BernardsCutToken(_token);

    tokenFractionProfitCalculatedTimes = 1;  //  idx 0 can not be used
  }

  /**
   * @dev Calculates token fraction profit.
   * TESTED
   */
  function calculateTokenFractionProfit() public onlyTokenHolder onlyCalculationEnabled {
    require(ongoingBernardFee >= 0.1 trx, "Not enough Bernardcut");
    uint256 fractionProfit = ongoingBernardFee.div(10000);
   
    tokenFractionProfitForCalculatedIdx[tokenFractionProfitCalculatedTimes] = fractionProfit;
    
    tokenFractionProfitCalculatedTimes = tokenFractionProfitCalculatedTimes.add(1);
    prevCalculationBlock = block.number;
    delete ongoingBernardFee;
  }
  
  /**
   * @dev Gets pending profit in BernardCut for sender.
   * @param _loopLimit  Limit of loops.
   * @return Profit amount.
   * TESTED
   */
  function pendingProfitInBernardCut(uint256 _loopLimit) public view returns(uint256 profit) {
    uint256 startIdx = profitWithdrawnOnCalculationIdx[msg.sender].add(1);
    
    if (startIdx < tokenFractionProfitCalculatedTimes) {
      uint256 endIdx = (tokenFractionProfitCalculatedTimes.sub(startIdx) > _loopLimit) ? startIdx.add(_loopLimit).sub(1) : tokenFractionProfitCalculatedTimes.sub(1);
      profit = _pendingProfit(msg.sender, startIdx, endIdx);
    }
  }
  
  /**
   * @dev Gets pending profit in BernardCut for address.
   * @param recipient  Recipient address.
   * @param _fromIdx  Index in tokenFractionProfitForCalculatedIdx to start on.
   * @param _toIdx  Index in tokenFractionProfitForCalculatedIdx to finish on.
   * @return Profit amount.
   * TESTED
   */
  function _pendingProfit(address recipient, uint256 _fromIdx, uint256 _toIdx) private view returns(uint256 profit) {
    uint256 priceSum;

    for (uint256 i = _fromIdx; i <= _toIdx; i ++) {
      priceSum = priceSum.add(tokenFractionProfitForCalculatedIdx[i]);
    }
    profit = priceSum.mul(token.balanceOf(recipient));
  }

  /**
   * @dev Withdraws profit for sender.
   * @param _loopLimit  Limit of loops.
   * TESTED
   */
  function withdrawProfit(uint256 _loopLimit) public onlyTokenHolder {
    _withdrawProfit(msg.sender, _loopLimit, false);
  }

  /**
   * @dev Withdraws profit for sender.
   * @param recipient  Recipient address.
   * @param _loopLimit  Limit of loops.
   * TESTED
   */
  function withdrawProfitFromToken(address payable recipient, uint256 _loopLimit) public onlyToken {
    _withdrawProfit(recipient, _loopLimit, true);
  }

  /**
   * @dev Withdraws profit for sender.
   * @param recipient  Recipient address.
   * @param _loopLimit  Limit of loops.
   * @param _fromToken  If sent from token, but EOA.
   * TESTED
   */
  function _withdrawProfit(address payable recipient, uint256 _loopLimit, bool _fromToken) private {
    uint256 startIdx = profitWithdrawnOnCalculationIdx[recipient].add(1);
    if (startIdx == tokenFractionProfitCalculatedTimes) {
      if (_fromToken) {
        profitWithdrawnOnCalculationIdx[recipient] = tokenFractionProfitCalculatedTimes.sub(1);
        return;
      }
      revert("Nothing to withdraw");
    }
    uint256 endIdx = (tokenFractionProfitCalculatedTimes.sub(startIdx) > _loopLimit) ? startIdx.add(_loopLimit).sub(1) : tokenFractionProfitCalculatedTimes.sub(1);
    uint256 profit = _pendingProfit(recipient, startIdx, endIdx);
    
    profitWithdrawnOnCalculationIdx[recipient] = endIdx;
    recipient.transfer(profit);
    emit BernardFeeWithdrawn(recipient, profit);
  }
}
