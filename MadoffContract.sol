pragma solidity 0.5.8;

import "./CountdownSessionManager.sol";
import "./BernardEscrow.sol";

contract MadoffContract is CountdownSessionManager, BernardEscrow {

  uint8 constant SHARE_PURCHASE_PERCENT_JACKPOT = 40;
  uint8 constant SHARE_PURCHASE_PERCENT_PURCHASED_SHARES = 50;
  uint8 constant SHARE_PURCHASE_PERCENT_BERNARD_WEBSITE = 5;  //  both has 5%

  uint8 constant JACKPOT_PERCENT_WINNER = 80;

  uint8 public ongoingStage;
  uint8 public maxStageNumber = 13;

  uint16[14] public blocksForStage =                    [21600,   18000,    14400,    10800,    7200,     3600,      1200,      600,       300,       100,       20,        10,         7,          4];
  uint32[14] public sharesForStageToPurchaseOriginal =  [2500,    5000,     3125,     12500,    10000,    62500,     62500,     400000,    390625,    2000000,   1562500,   10000000,   12500000,   25000000];
  uint32[14] public sharesForStageToPurchase =          [2500,    5000,     3125,     12500,    10000,    62500,     62500,     400000,    390625,    2000000,   562500,    10000000,   12500000,   25000000];
  uint256[14] public sharePriceForStage =               [10 trx,  20 trx,   40 trx,   80 trx,   125 trx,  160 trx,   200 trx,   250 trx,   320 trx,   500 trx,   800 trx,   1000 trx,   1000 trx,   1000 trx];
  
  uint256 public latestPurchaseBlock;
  uint256 public ongoingJackpot;
  address public ongoingWinner;
  mapping(address => uint256) public websiteFee;
  mapping(address => uint256) public jackpotForAddr;

  event JackpotWithdrawn(address indexed to, uint256 indexed amount);
  event WebsiteFeeWithdrawn(address indexed to, uint256 indexed amount);
  event Purchase(address indexed from, uint256 indexed sharesNumber);
  event GameRestarted();
 
  /**
   * @dev Contract constructor.
   * @param _token Token address.
   * TESTED
   */
  constructor(address _token) BernardEscrow(_token) public {
  }

  /**
   * @dev Purchases share(s).
   * @param _websiteAddr Website address, that trx was sent from.
   * TESTED
   */
  function purchase(address _websiteAddr) public payable returns(uint256) {
    if (latestPurchaseBlock == 0) {
        latestPurchaseBlock = block.number;
    } else if (ongoingStage > maxStageNumber) {
      ongoingStageDurationExceeded();
      emit GameRestarted();
    } else if (block.number > latestPurchaseBlock.add(blocksForStage[ongoingStage])) {
      ongoingStageDurationExceeded();
    }

    //  jackpot
    uint256 partJackpot = msg.value.mul(uint256(SHARE_PURCHASE_PERCENT_JACKPOT)).div(uint256(100));
    ongoingJackpot = ongoingJackpot.add(partJackpot);

    //  ongoingBernardFee
    uint256 partBernardWebsiteFee = msg.value.mul(uint256(SHARE_PURCHASE_PERCENT_BERNARD_WEBSITE)).div(uint256(100));
    ongoingBernardFee = ongoingBernardFee.add(partBernardWebsiteFee);

    //  websiteFee
    if (_websiteAddr == address(0)) {
      ongoingBernardFee = ongoingBernardFee.add(partBernardWebsiteFee);
    } else {
      websiteFee[_websiteAddr] = websiteFee[_websiteAddr].add(partBernardWebsiteFee);
    }

    //  shares
    uint256 shares = getSharesAndUpdateOngoingStageInfo(msg.value);
    require(shares > 0, "Min 1 share");
    
    //  previous shares
    uint256 partPreviousShares = msg.value.mul(uint256(SHARE_PURCHASE_PERCENT_PURCHASED_SHARES)).div(uint256(100));
    if (sessionsInfo[ongoingSessionIdx].sharesPurchased == 0) {
      ongoingBernardFee = ongoingBernardFee.add(partPreviousShares);
      delete partPreviousShares;
    }
    sharesPurchased(shares, msg.sender, partPreviousShares);
    
    latestPurchaseBlock = block.number;
    ongoingWinner = msg.sender;

    emit Purchase(ongoingWinner, shares);
  }
  
  /**
   * @dev Duration for ongoing stage exceeded.
   * TESTED
   */
  function ongoingStageDurationExceeded() private {
    uint256 jptTmp = ongoingJackpot;
    delete ongoingJackpot;

    //  winner - 80%
    uint256 winnerJptPart = jptTmp.mul(uint256(JACKPOT_PERCENT_WINNER)).div(uint256(100));
    jackpotForAddr[ongoingWinner] = jackpotForAddr[ongoingWinner].add(winnerJptPart);

    //  previous shares - 20%
    uint256 prevSharesPart = jptTmp.sub(winnerJptPart);
    countdownWasReset(prevSharesPart);
    
    sharesForStageToPurchase = sharesForStageToPurchaseOriginal;

    delete ongoingWinner;
    delete ongoingStage;
  }

  /**
   * @dev Calculates share number and increase ongoing stage if needed.
   * @param _amount Funds amount.
   * @return Shares number.
   * TESTED
   */
  function getSharesAndUpdateOngoingStageInfo(uint256 _amount) private returns(uint256) {
    bool loop = true;
    uint256 resultShares;
    uint256 valueToSpend = _amount;
    uint256 valueSpent;

    do {
      uint256 sharesForOngoingStage = getShares(ongoingStage, valueToSpend);
      
      if (sharesForOngoingStage <= sharesForStageToPurchase[ongoingStage]) {
        resultShares = resultShares.add(sharesForOngoingStage);
        sharesForStageToPurchase[ongoingStage] = uint32(uint256(sharesForStageToPurchase[ongoingStage]).sub(sharesForOngoingStage));

        valueSpent = sharesForOngoingStage.mul(sharePriceForStage[ongoingStage]);
        valueToSpend = valueToSpend.sub(valueSpent);

        if (sharesForStageToPurchase[ongoingStage] == 0) {
          ongoingStage += 1;
        }

        loop = false;
      } else {
        valueSpent = uint256(sharesForStageToPurchase[ongoingStage]).mul(sharePriceForStage[ongoingStage]);
        valueToSpend = valueToSpend.sub(valueSpent);
        resultShares = resultShares.add(sharesForStageToPurchase[ongoingStage]);

        delete sharesForStageToPurchase[ongoingStage];
        ongoingStage += 1;
      }
    } while (loop); 

    require(valueToSpend == 0, "Wrong value sent");  //  should be no unspent amount

    return resultShares;
  }

  /**
   * @dev Calculates share number.
   * @param _stage Stage to be used.
   * @param _amount Funds amount.
   * @return Shares number.
   * TESTED
   */
  function getShares(uint8 _stage, uint256 _amount) private view returns(uint256 shares) {
    require(_stage <= maxStageNumber, "Stage overflow");

    uint256 sharePrice = sharePriceForStage[_stage];
    shares = _amount.div(uint256(sharePrice));
  }

  //  WITHDRAW

  /**
   * @dev Withdraws website fee.
   * TESTED
   */
  function withdrawWebsiteFee() public {
    uint256 feeTmp = websiteFee[msg.sender];
    require(feeTmp > 0, "No fee");
    delete websiteFee[msg.sender];
    
    msg.sender.transfer(feeTmp);
    emit WebsiteFeeWithdrawn(msg.sender, feeTmp);
  }

  /**
   * @dev Withdraws jackpot.
   * TESTED
   */
  function withdrawJackpot() public {
    uint256 jptTmp = jackpotForAddr[msg.sender];
    require(jptTmp > 0, "No jackpot");
    delete jackpotForAddr[msg.sender];
    
    msg.sender.transfer(jptTmp);
    emit JackpotWithdrawn(msg.sender, jptTmp);
  }
}
