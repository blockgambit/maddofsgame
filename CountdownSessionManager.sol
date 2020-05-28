pragma solidity 0.5.8;

import "./SafeMath.sol";


contract CountdownSessionManager {
  using SafeMath for uint256;

  struct PurchaseInfo {
    address purchaser;
    uint256 shareNumber;
    uint256 previousSharePrice;
  }

  struct ProfitWithdrawalInfo {
    bool jackpotForSharesWithdrawn;
    mapping (uint256 => uint256) purchaseProfitWithdrawnOnPurchase; //  share profit, made in Purchase, withdrawn until including Purchase idx in Session, PurchaseMade => PurchaseWithdrawn
  }

  //  starts from S1 first purchase
  struct SessionInfo {
    uint256 sharesPurchased;    //  shares purchased during ongoing Session
    uint256 jackpotSharePrice;  //  share price after jackpot calculation for ongoing Session
    
    PurchaseInfo[] purchasesInfo;
    mapping (address => uint256[]) purchaseIdxsForPurchaser;  //  Purchase idxs within Session, for purchaser
    mapping (address => uint256) sharesPurchasedByPurchaser;  //  number of shares purchased by Purchaser during Session
    mapping (address => ProfitWithdrawalInfo) profitWithdrawalInfoForPurchaser;  //  information about address profit withdrawal
  }

  uint256 public ongoingSessionIdx;

  mapping (uint256 => SessionInfo) internal sessionsInfo; //  Sessions info, new Session after countdown reset
  mapping (address => uint256[]) private sessionsInfoForPurchaser; //  sessions, where purchaser participated
  
  event SharesProfitWithdrawn(address _address, uint256 _amount, uint256 _session, uint256 _purchase);
  event JackpotForSharesProfitWithdrawn(address _address, uint256 _amount, uint256 _session);


  //  SHARES PURCHASED
  /**
   * @dev Creates new Purchase and add in to list.
   * @param _shareNumber Number of shares.
   * @param _purchaser Purchaser address.
   * @param _rewardForPreviousShares Reward amount for previously purchased shares.
   * TESTED
   */
  function sharesPurchased(uint256 _shareNumber, address _purchaser, uint256 _rewardForPreviousShares) internal {
    require(_shareNumber > 0, "Wrong _shareNumber");
    require(_purchaser != address(0), "Wrong _purchaser");

    SessionInfo storage session = sessionsInfo[ongoingSessionIdx];
    uint256 sharePrice = (_rewardForPreviousShares == 0) ? 0 : _rewardForPreviousShares.div(session.sharesPurchased);
    session.purchaseIdxsForPurchaser[_purchaser].push(session.purchasesInfo.length);
    session.purchasesInfo.push(PurchaseInfo({purchaser: _purchaser, shareNumber: _shareNumber, previousSharePrice: sharePrice}));
    session.sharesPurchasedByPurchaser[_purchaser] = session.sharesPurchasedByPurchaser[_purchaser].add(_shareNumber);
    
    session.sharesPurchased = session.sharesPurchased.add(_shareNumber);
    addSessionForPurchaser(ongoingSessionIdx, _purchaser);
  }

  /**
   * @dev Adds session idx for purchaser.
   * @param _session Session idx.
   * @param _purchaser Purchaser address.
   * TESTED
   */
  function addSessionForPurchaser(uint256 _session, address _purchaser) private {
    uint256[] storage sessionsForPurchaser = sessionsInfoForPurchaser[_purchaser];
    if (sessionsForPurchaser.length == 0) {
      sessionsInfoForPurchaser[_purchaser].push(_session);
    } else if (sessionsForPurchaser[sessionsForPurchaser.length - 1] < _session) {
      sessionsInfoForPurchaser[_purchaser].push(_session);
    }
  }

  //  SESSION COUNTDOWN RESET
  /**
   * @dev Creates new Session on countdown for previous Session reset.
   * @param _prevSharesPart Funds amount, that should be used as reward for previously purchased shares.
   * TESTED
   */
  function countdownWasReset(uint256 _prevSharesPart) internal {
    SessionInfo storage session = sessionsInfo[ongoingSessionIdx];
    uint256 sharePrice = _prevSharesPart.div(session.sharesPurchased);
    session.jackpotSharePrice = sharePrice;
    
    ongoingSessionIdx = ongoingSessionIdx.add(1);
  }

  //  PROFIT
  
  //  1. jackpot for purchased shares in Session
  /**
   * @dev Calculates jackpot for purchased shares for Session for purchaser.
   * @param _session Session idx.
   * TESTED
   */
  function jackpotForSharesInSessionForUser(uint256 _session) public view returns(uint256 profit) {
    SessionInfo storage sessionInfo = sessionsInfo[_session];

    uint256 sharePrice = sessionInfo.jackpotSharePrice;
    require(sharePrice > 0, "No jackpot yet");

    uint256 sharesPurchasedByPurchaser = sessionInfo.sharesPurchasedByPurchaser[msg.sender];
    require(sharesPurchasedByPurchaser > 0, "No shares");

    profit = sharePrice.mul(sharesPurchasedByPurchaser);
  }

  /**
   * @dev Withdraws jackpot for purchased shares for Session for purchaser.
   * @param _session Session idx.
   * TESTED
   */
  function withdrawjackpotForSharesInSession(uint256 _session) public {
    SessionInfo storage session = sessionsInfo[_session];
    ProfitWithdrawalInfo storage profitWithdrawalInfo = session.profitWithdrawalInfoForPurchaser[msg.sender];
    require(profitWithdrawalInfo.jackpotForSharesWithdrawn == false, "Already withdrawn");
    
    profitWithdrawalInfo.jackpotForSharesWithdrawn = true;
    uint256 profit = jackpotForSharesInSessionForUser(_session);

    msg.sender.transfer(profit);
    emit JackpotForSharesProfitWithdrawn(msg.sender, profit, _session);
  }

  //  2. shares profit for Purchase in Session
  /**
   * @dev Calculates profit for Purchase for Session.
   * @param _purchase Purchase idx.
   * @param _session Session idx.
   * @param _fromPurchase Purchase idx to start on.
   * @param _toPurchase Purchase idx to end on.
   * @return Profit amount.
   * TESTED
   */
  function profitForPurchaseInSession(uint256 _purchase, uint256 _session, uint256 _fromPurchase, uint256 _toPurchase) public view returns(uint256 profit) {
    require(_fromPurchase > _purchase, "Wrong _fromPurchase");
    require(_toPurchase >= _fromPurchase, "Wrong _toPurchase");

    SessionInfo storage session = sessionsInfo[_session];
    PurchaseInfo storage purchaseInfo = session.purchasesInfo[_purchase];

    require(_toPurchase <= session.purchasesInfo.length.sub(1), "_toPurchase exceeds");

    uint256 shares = purchaseInfo.shareNumber;

    for (uint256 i = _fromPurchase; i <= _toPurchase; i ++) {
      uint256 sharePrice = session.purchasesInfo[i].previousSharePrice;
      uint256 profitTmp = shares.mul(sharePrice);
      profit = profit.add(profitTmp);
    }
  }

  /**
   * @dev Withdraws profit for Purchase for Session.
   * @param _purchase Purchase idx.
   * @param _session Session idx.
   * @param _loopLimit Loop limit.
   * TESTED
   */
  function withdrawProfitForPurchaseInSession(uint256 _purchase, uint256 _session, uint256 _loopLimit) public {
    require(_loopLimit > 0, "Wrong _loopLimit");

    SessionInfo storage session = sessionsInfo[_session];
    require(_purchase < session.purchasesInfo.length, "_purchase exceeds");

    PurchaseInfo storage purchaseInfo = session.purchasesInfo[_purchase];
    require(purchaseInfo.purchaser == msg.sender, "Not purchaser");

    uint256 purchaseIdxWithdrawnOn = purchaseProfitInSessionWithdrawnOnPurchaseForUser(_purchase, _session);
    uint256 fromPurchaseIdx = (purchaseIdxWithdrawnOn == 0) ? _purchase.add(1) : purchaseIdxWithdrawnOn.add(1);
    
    uint256 toPurchaseIdx = session.purchasesInfo.length.sub(1);
    require(fromPurchaseIdx <= toPurchaseIdx, "No more profit");

    if (toPurchaseIdx.sub(fromPurchaseIdx).add(1) > _loopLimit) {
      toPurchaseIdx = fromPurchaseIdx.add(_loopLimit).sub(1);
    }

    uint256 profit = profitForPurchaseInSession(_purchase, _session, fromPurchaseIdx, toPurchaseIdx);

    sessionsInfo[_session].profitWithdrawalInfoForPurchaser[msg.sender].purchaseProfitWithdrawnOnPurchase[_purchase] = toPurchaseIdx;
    
    msg.sender.transfer(profit);
    emit SharesProfitWithdrawn(msg.sender, profit, _session, _purchase);
  }
  

  //  VIEW

  /**
   * @dev Gets session idxs, where user made purchase.
   * @return Session idxs.
   * TESTED
   */
  function participatedSessionsForUser() public view returns(uint256[] memory sessions) {
    sessions = sessionsInfoForPurchaser[msg.sender];
  }

  //  SessionInfo
  /**
   * @dev Gets total shares purchased in Session.
   * @param _session Session idx.
   * @return Number of shares.
   * TESTED
   */
  function sharesPurchasedInSession(uint256 _session) public view returns(uint256 shares) {
    shares = sessionsInfo[_session].sharesPurchased;
  }
  
  /**
   * @dev Gets jackpot share price in Session.
   * @param _session Session idx.
   * @return Share price.
   * TESTED
   */
  function jackpotSharePriceInSession(uint256 _session) public view returns(uint256 price) {
    price = sessionsInfo[_session].jackpotSharePrice;
  }

  /**
   * @dev Gets number of purchases in Session.
   * @param _session Session idx.
   * @return Number of purchases.
   * TESTED
   */
  function purchaseCountInSession(uint256 _session) public view returns(uint256 purchases) {
    purchases = sessionsInfo[_session].purchasesInfo.length;
  }

  /**
   * @dev Gets purchase info in Session.
   * @param _purchase Purchase idx.
   * @param _session Session idx.
   * @return Purchaser address, Number of purchased shares, share price for previously purchased shares.
   * TESTED
   */
  function purchaseInfoInSession(uint256 _purchase, uint256 _session) public view returns (address purchaser, uint256 shareNumber, uint256 previousSharePrice) {
    SessionInfo storage session = sessionsInfo[_session];
    PurchaseInfo storage purchase = session.purchasesInfo[_purchase];
    return (purchase.purchaser, purchase.shareNumber, purchase.previousSharePrice);
  }

  /**
   * @dev Gets purchase idx in Session for purchaser.
   * @param _session Session idx.
   * @return Purchase idxs.
   * TESTED
   */
  function purchasesInSessionForUser(uint256 _session) public view returns(uint256[] memory purchases) {
    purchases = sessionsInfo[_session].purchaseIdxsForPurchaser[msg.sender];
  }
  
  /**
   * @dev Gets number of shares purchased in Session for purchaser.
   * @param _session Session idx.
   * @return Shares number.
   * TESTED
   */
  function sharesPurchasedInSessionByPurchaser(uint256 _session) public view returns(uint256 shares) {
    shares = sessionsInfo[_session].sharesPurchasedByPurchaser[msg.sender];
  }

  //  ProfitWithdrawalInfo
  /**
   * @dev Checks if purchaser withdrawn jackpot for purchased shares in Session.
   * @param _session Session idx.
   * @return Withdrawn or not.
   * TESTED
   */
  function isJackpotForSharesInSessionWithdrawnForUser(uint256 _session) public view returns(bool withdrawn) {
    withdrawn = sessionsInfo[_session].profitWithdrawalInfoForPurchaser[msg.sender].jackpotForSharesWithdrawn;
  }

  /**
   * @dev Gets purchase idx, on which profit for Purchase was withdrawn.
   * @param _purchase Purchase idx.
   * @param _session Session idx.
   * @return Purchase idx.
   * TESTED
   */
  function purchaseProfitInSessionWithdrawnOnPurchaseForUser(uint256 _purchase, uint256 _session) public view returns(uint256 purchase) {
    purchase = sessionsInfo[_session].profitWithdrawalInfoForPurchaser[msg.sender].purchaseProfitWithdrawnOnPurchase[_purchase];
  }
}
