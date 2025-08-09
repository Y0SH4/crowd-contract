//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

enum Rank {
  Newbie,
  Rare,
  SuperRare,
  Epic,
  Legend,
  SuperLegend
}

/**
 * @dev The struct of account information
 * @param referrer The referrer addresss
 * @param downlineCount The total referral amount of an address
 * @param isRegistered The indicator of whether the address is registered and paid fee
 */
struct Account {
  Rank rank;
  bool isRegistered;
  address referrer;
  uint256 downlineCount;
  uint256 nftSalesCount;
  uint256 rankUpdatedAt;
  uint256 rankRewardClaimedAt;
  bool isLeader;
  uint256 omzet;
}

/**
 * @dev The struct for calculating distribution value
 * based on registration fee
 */
struct RewardValues {
  uint256 lvl1;
  uint256 lvl2;
  uint256 lvl3;
  uint256 globalOmzet;
  uint256 nftSales;
}

/**
 * @dev The struct for storing address list
 */
struct AddressList {
  address admin;
  address root1;
  address root2;
  address root3;
  address feeReceiver;
}

struct PoolReward {
  uint256 claimable;
  uint256 valueLeft;
}

struct State {
  bool isClaimable;
  uint256 claimableOpenedAt;
  uint256 rareRankCount;
  uint256 superRareRankCount;
  uint256 epicRankCount;
  uint256 legendRankCount;
  uint256 superLegendRankCount;
}

contract CrowdNetwork is Initializable, OwnableUpgradeable {
  using SafeMath for uint256;

  event Registration(address referee, address referrer);
  event PoolGlobalOmzetReserved(address from, uint256 amount);
  event PoolTopSalesReserved(address from, uint256 amount);
  event RewardGiven(address from, address to, uint256 amount);
  event RewardClaimed(address from, uint256 amount);
  event RankRewardClaimed(address from, uint256 amount);
  // create event to track nft sales reward
  event NftSalesRewardClaimed(address from, uint256 amount);
  event ClaimingSessionStarted(uint256 startedAt);
  event ClaimingSessionEnded(uint256 endedAt);
  event RegistrationFeeUpdated(uint256 amount);
  // track transfer account to another address
  event AccountTransferred(address from, address to);
  event LeaderStatusChanged(address indexed user, bool isLeader);
  event OmzetUpdated(address indexed buyer, uint256 amount);
  event NftSalesRewardPaid(address to, uint256 amount);

  mapping(address => Account) public accounts;
  mapping(address => uint256) public rewards;
  mapping(int8 => PoolReward) public poolRewards;
  State private state;

  uint256 public registrationFee;
  AddressList public addressList;
  // store address rank regarding to nft sales based on total nft sales count
  address[10] public topNftSalesRank;

  // PoolReward public poolReward;
  RewardValues public rewardValues;
  address public nftContractAddress;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}

  function initialize(
    uint256 _registrationFee,
    address payable _adminAddress,
    address payable _feeReceiver,
    address payable _root1Address,
    address payable _root2Address,
    address payable _root3Address
  ) public initializer {
    __Ownable_init();
    registrationFee = _registrationFee;
    addressList.admin = _adminAddress;
    addressList.feeReceiver = _feeReceiver;

    // root address
    addressList.root1 = _root1Address;
    accounts[_root1Address].isRegistered = true;
    accounts[_root1Address].downlineCount = 2;

    addressList.root2 = _root2Address;
    accounts[_root2Address].isRegistered = true;
    accounts[_root2Address].downlineCount = 1;
    accounts[_root2Address].referrer = _root1Address;

    addressList.root3 = _root3Address;
    accounts[_root3Address].isRegistered = true;
    accounts[_root3Address].referrer = _root2Address;

    rewardValues.lvl1 = _registrationFee.mul(30).div(100);
    rewardValues.lvl2 = _registrationFee.mul(15).div(100);
    rewardValues.lvl3 = _registrationFee.mul(5).div(100);
    rewardValues.globalOmzet = 0;
    rewardValues.nftSales = _registrationFee.mul(25).div(100);

    Account storage adminAccount = accounts[_adminAddress];
    adminAccount.isRegistered = true;
  }

  function setNftContractAddress(address _nftContractAddress) public onlyOwner {
    require(
      _nftContractAddress != address(0),
      "NFT contract address cannot be zero"
    );
    nftContractAddress = _nftContractAddress;
  }

  /**
   * @dev update registration fee and recalculate reward value
   */
  function updateRegistrationFee(uint256 feeValue) public onlyOwner {
    registrationFee = feeValue;

    rewardValues.lvl1 = feeValue.mul(30).div(100);
    rewardValues.lvl2 = feeValue.mul(15).div(100);
    rewardValues.lvl3 = feeValue.mul(5).div(100);
    rewardValues.globalOmzet = 0;
    rewardValues.nftSales = feeValue.mul(25).div(100);
    emit RegistrationFeeUpdated(feeValue);
  }

  /**
   * @dev Update omzet for buyer and all uplines up to 20 levels
   * @param buyer The address of NFT buyer
   * @param amount The NFT price amount
   */
  function updateOmzet(address buyer, uint256 amount) external {
    require(
      msg.sender == nftContractAddress,
      "Only NFT contract can call this"
    );
    require(nftContractAddress != address(0), "NFT contract not set");
    require(accounts[buyer].isRegistered, "Buyer must be registered");

    // Update omzet untuk buyer sendiri
    accounts[buyer].omzet = accounts[buyer].omzet.add(amount);

    // Update omzet untuk semua upline hingga 20 level
    Account storage _currentUser = accounts[buyer];
    for (uint256 i = 0; i < 20; i++) {
      address _parent = _currentUser.referrer;

      // Jika sudah sampai root atau tidak ada referrer, break
      if (_parent == address(0)) {
        break;
      }

      // Update omzet parent
      Account storage _parentAccount = accounts[_parent];
      _parentAccount.omzet = _parentAccount.omzet.add(amount);

      // Pindah ke parent untuk iterasi selanjutnya
      _currentUser = _parentAccount;
    }

    emit OmzetUpdated(buyer, amount);
  }

  /**
   * @dev Get total omzet of an address
   * @param addr The address to check
   * @return Total omzet amount
   */
  function getOmzet(address addr) public view returns (uint256) {
    return accounts[addr].omzet;
  }

  /**
   * @dev Get omzet and other account info
   * @param addr The address to check
   * @return rank The rank of the account
   * @return registered Whether the account is registered
   * @return referrer The referrer address
   * @return downlineCount The number of downlines
   * @return omzet The total omzet of the account
   */
  function getAccountInfo(
    address addr
  )
    public
    view
    returns (
      Rank rank,
      bool registered,
      address referrer,
      uint256 downlineCount,
      uint256 omzet
    )
  {
    Account storage account = accounts[addr];
    return (
      account.rank,
      account.isRegistered,
      account.referrer,
      account.downlineCount,
      account.omzet
    );
  }

  /**
   * @dev claim rewards
   */
  function claimRewards() public returns (bool) {
    require(rewards[msg.sender] > 0, "No rewards to claim");
    uint256 c = rewards[msg.sender];
    rewards[msg.sender] = 0;

    if (msg.sender != addressList.admin) {
      uint256 tenPercent = c.mul(10).div(100);
      c = c.sub(tenPercent);
      payable(addressList.feeReceiver).transfer(tenPercent);
    }

    payable(msg.sender).transfer(c);
    emit RewardClaimed(msg.sender, c);
    return true;
  }

  /**
   * @dev check unclaimed reward of an address
   */
  function getUnclaimedReward(address _address) public view returns (uint256) {
    return rewards[_address];
  }

  /**
   * @dev get the referrer of an address
   */
  function getReferrer(address addr) public view returns (address) {
    return accounts[addr].referrer;
  }

  /**
   * @dev Utils function for check whether an address has the referrer
   */
  function hasReferrer(address addr) public view returns (bool) {
    return accounts[addr].referrer != address(0);
  }

  function getTotalRareCount() public view returns (uint256) {
    return state.rareRankCount;
  }

  function getTotalSuperRareCount() public view returns (uint256) {
    return state.superRareRankCount;
  }

  function getTotalEpicCount() public view returns (uint256) {
    return state.epicRankCount;
  }

  function rankRewardClaimableAt() public view returns (uint256) {
    return state.claimableOpenedAt;
  }

  function getTotalLegendCount() public view returns (uint256) {
    return state.legendRankCount;
  }

  function getTotalSuperLegendCount() public view returns (uint256) {
    return state.superLegendRankCount;
  }
  /**
   * @dev Check whether an address is registered
   * @param addr The address to check
   */
  function isRegistered(address addr) public view returns (bool) {
    return accounts[addr].isRegistered;
  }

  // i commented this function because it is not used anymore the velue is sent directly to feeReceiver
  // function storeNftSalesReward() private {
  //   PoolReward storage nftSales = poolRewards[0];
  //   nftSales.claimable = nftSales.claimable.add(rewardValues.nftSales);
  // }

  function storeGlobalOmzetReward() private {
    PoolReward storage globalOmzet = poolRewards[1];
    globalOmzet.claimable = globalOmzet.claimable.add(rewardValues.globalOmzet);
  }

  /**
   * @dev Check whether rank reward can be claimed
   */
  function isRankRewardClaimable() public view returns (bool) {
    return state.isClaimable;
  }

  function claimMyRankReward() public {
    require(state.isClaimable, "Reward is not claimable");
    require(
      accounts[msg.sender].rankRewardClaimedAt < state.claimableOpenedAt,
      "Reward is already claimed"
    );
    Account storage _account = accounts[msg.sender];
    require(_account.rank != Rank.Newbie, "not eligible");
    uint256 rewardAmount = getMyRankReward();
    PoolReward storage globalOmzet = poolRewards[1];

    if (_account.rank == Rank.Rare) {
      PoolReward storage rareReward = poolRewards[2];
      if (rareReward.valueLeft < rewardAmount) {
        rewardAmount = rareReward.valueLeft;
      }
      uint256 tenPercent = rewardAmount.mul(10).div(100);
      payable(addressList.feeReceiver).transfer(tenPercent);
      rewardAmount = rewardAmount.sub(tenPercent);

      payable(msg.sender).transfer(rewardAmount);
      emit RankRewardClaimed(msg.sender, rewardAmount);
      rewardAmount = rewardAmount.add(tenPercent);
      rareReward.valueLeft = rareReward.valueLeft.sub(rewardAmount);
    }

    if (_account.rank == Rank.SuperRare) {
      PoolReward storage superRareReward = poolRewards[3];
      if (superRareReward.valueLeft < rewardAmount) {
        rewardAmount = superRareReward.valueLeft;
      }

      uint256 tenPercent = rewardAmount.mul(10).div(100);
      payable(addressList.feeReceiver).transfer(tenPercent);
      rewardAmount = rewardAmount.sub(tenPercent);

      payable(msg.sender).transfer(rewardAmount);
      emit RankRewardClaimed(msg.sender, rewardAmount);
      rewardAmount = rewardAmount.add(tenPercent);
      superRareReward.valueLeft = superRareReward.valueLeft.sub(rewardAmount);
    }

    if (_account.rank == Rank.Epic) {
      PoolReward storage epicReward = poolRewards[4];
      if (epicReward.valueLeft < rewardAmount) {
        rewardAmount = epicReward.valueLeft;
      }

      uint256 tenPercent = rewardAmount.mul(10).div(100);
      payable(addressList.feeReceiver).transfer(tenPercent);
      rewardAmount = rewardAmount.sub(tenPercent);

      payable(msg.sender).transfer(rewardAmount);
      emit RankRewardClaimed(msg.sender, rewardAmount);
      rewardAmount = rewardAmount.add(tenPercent);
      epicReward.valueLeft = epicReward.valueLeft.sub(rewardAmount);
    }

    if (_account.rank == Rank.Legend) {
      PoolReward storage legendReward = poolRewards[5];
      if (legendReward.valueLeft < rewardAmount) {
        rewardAmount = legendReward.valueLeft;
      }

      uint256 tenPercent = rewardAmount.mul(10).div(100);
      payable(addressList.feeReceiver).transfer(tenPercent);
      rewardAmount = rewardAmount.sub(tenPercent);

      payable(msg.sender).transfer(rewardAmount);
      emit RankRewardClaimed(msg.sender, rewardAmount);
      rewardAmount = rewardAmount.add(tenPercent);
      legendReward.valueLeft = legendReward.valueLeft.sub(rewardAmount);
    }

    if (_account.rank == Rank.SuperLegend) {
      PoolReward storage superLegendReward = poolRewards[6];
      if (superLegendReward.valueLeft < rewardAmount) {
        rewardAmount = superLegendReward.valueLeft;
      }

      uint256 tenPercent = rewardAmount.mul(10).div(100);
      payable(addressList.feeReceiver).transfer(tenPercent);
      rewardAmount = rewardAmount.sub(tenPercent);

      payable(msg.sender).transfer(rewardAmount);
      emit RankRewardClaimed(msg.sender, rewardAmount);
      rewardAmount = rewardAmount.add(tenPercent);
      superLegendReward.valueLeft = superLegendReward.valueLeft.sub(
        rewardAmount
      );
    }

    _account.rankRewardClaimedAt = block.timestamp;

    globalOmzet.valueLeft = globalOmzet.valueLeft.sub(rewardAmount);
  }

  // i commented this function because it is not used anymore the velue is sent directly to feeReceiver
  // function claimNftSales() public returns (bool) {
  //   PoolReward storage nftSales = poolRewards[0];
  //   nftSales.valueLeft = nftSales.claimable;

  //   require(nftSales.claimable > 0, "Reward is already claimed");
  //   require(
  //     msg.sender == addressList.feeReceiver,
  //     "Only fee receiver can claim"
  //   );

  //   payable(addressList.feeReceiver).transfer(nftSales.valueLeft);
  //   emit NftSalesRewardClaimed(msg.sender, nftSales.valueLeft);

  //   //reset the pool
  //   nftSales.claimable = nftSales.claimable.sub(nftSales.valueLeft);
  //   nftSales.valueLeft = 0;
  //   return true;
  // }

  function changeJobAddress(address _feeReceiver) public onlyOwner {
    require(_feeReceiver != address(0), "Fee Address Required");
    addressList.feeReceiver = _feeReceiver;
  }

  function changeAdminAddress(address _newAdminAddres) public onlyOwner {
    require(_newAdminAddres != address(0), "address can't be null");
    // get all state
    address prevAdminAddrs = addressList.admin;
    uint prevAdminReward = rewards[prevAdminAddrs];

    // set to new address
    addressList.admin = _newAdminAddres;
    rewards[_newAdminAddres] = prevAdminReward;

    // reset old admin rewards
    rewards[prevAdminAddrs] = 0;
  }

  function getMyRankReward() public view returns (uint256) {
    Account storage _account = accounts[msg.sender];

    if (accounts[msg.sender].rankRewardClaimedAt >= state.claimableOpenedAt) {
      return 0;
    }

    if (_account.rank == Rank.Newbie) {
      return 0;
    }

    if (_account.rank == Rank.Rare && state.rareRankCount > 0) {
      PoolReward storage rareReward = poolRewards[2];
      return rareReward.claimable.div(state.rareRankCount);
    }

    if (_account.rank == Rank.SuperRare) {
      PoolReward storage superRareReward = poolRewards[3];
      return superRareReward.claimable.div(state.superRareRankCount);
    }

    if (_account.rank == Rank.Epic) {
      PoolReward storage epicReward = poolRewards[4];
      return epicReward.claimable.div(state.epicRankCount);
    }

    if (_account.rank == Rank.Legend) {
      PoolReward storage legendReward = poolRewards[5];
      return legendReward.claimable.div(state.legendRankCount);
    }

    if (_account.rank == Rank.SuperLegend) {
      PoolReward storage superLegendReward = poolRewards[6];
      return superLegendReward.claimable.div(state.superLegendRankCount);
    }

    return 0;
  }

  function startClaimingRankRewards() public onlyOwner {
    require(!state.isClaimable, "already started");
    state.isClaimable = true;
    state.claimableOpenedAt = block.timestamp;

    PoolReward storage globalOmzet = poolRewards[1];
    globalOmzet.valueLeft = globalOmzet.claimable;
    globalOmzet.claimable = globalOmzet.claimable.sub(globalOmzet.valueLeft);

    uint256 valueLeft = globalOmzet.valueLeft;

    // Rare Pool
    PoolReward storage rareReward = poolRewards[2];
    // 12.85714286%
    rareReward.valueLeft = globalOmzet.valueLeft.mul(1285714286).div(
      10000000000
    );
    rareReward.claimable = rareReward.valueLeft;
    valueLeft = valueLeft.sub(rareReward.valueLeft);

    // Super Rare Pool
    PoolReward storage superRareReward = poolRewards[3];
    // 18.57142857%
    superRareReward.valueLeft = globalOmzet.valueLeft.mul(1857142857).div(
      10000000000
    );
    superRareReward.claimable = superRareReward.valueLeft;
    valueLeft = valueLeft.sub(superRareReward.valueLeft);

    // Epic Pool
    PoolReward storage epicReward = poolRewards[4];
    // 21.42857134%
    epicReward.valueLeft = globalOmzet.valueLeft.mul(2142857134).div(
      10000000000
    );
    epicReward.claimable = epicReward.valueLeft;
    valueLeft = valueLeft.sub(epicReward.valueLeft);

    // Legend Pool
    PoolReward storage legendReward = poolRewards[5];
    // 22.85714286%
    legendReward.valueLeft = globalOmzet.valueLeft.mul(2285714286).div(
      10000000000
    );
    legendReward.claimable = legendReward.valueLeft;
    valueLeft = valueLeft.sub(legendReward.valueLeft);

    // SuperLegend Pool
    PoolReward storage superLegendReward = poolRewards[6];
    // 24.28571429%
    superLegendReward.valueLeft = valueLeft;
    superLegendReward.claimable = superLegendReward.valueLeft;
    emit ClaimingSessionStarted(block.timestamp);
  }

  function stopClaimingRankRewards() public onlyOwner {
    require(state.isClaimable, "not yet started");

    state.isClaimable = false;

    PoolReward storage globalOmzet = poolRewards[1];
    globalOmzet.claimable = globalOmzet.claimable.add(globalOmzet.valueLeft);
    globalOmzet.valueLeft = 0;

    // Rare Pool
    PoolReward storage rareReward = poolRewards[2];
    rareReward.valueLeft = 0;
    rareReward.claimable = 0;

    // Super Rare Pool
    PoolReward storage superRareReward = poolRewards[3];
    superRareReward.valueLeft = 0;
    superRareReward.claimable = 0;

    // Epic Pool
    PoolReward storage epicReward = poolRewards[4];
    epicReward.valueLeft = 0;
    epicReward.claimable = 0;

    // Legend Pool
    PoolReward storage legendReward = poolRewards[5];
    legendReward.valueLeft = 0;
    legendReward.claimable = 0;

    // SuperLegend Pool
    PoolReward storage superLegendReward = poolRewards[6];
    superLegendReward.valueLeft = 0;
    superLegendReward.claimable = 0;

    emit ClaimingSessionEnded(block.timestamp);
  }

  /**
   * @dev register an address and set the referrer
   * @param referrer The address would set as referrer of msg.sender
   * @return whether success to add upline
   */
  function register(address payable referrer) public payable returns (bool) {
    require(!state.isClaimable, "Registration Closed");
    require(referrer != addressList.admin, "Referrer Not Permitted");
    require(referrer != addressList.feeReceiver, "Referrer Not Permitted");
    require(msg.sender != addressList.admin, "Address Not Permitted");
    require(msg.sender != addressList.feeReceiver, "Address Not Permitted");
    require(msg.value >= registrationFee, "Registration fee is not enough");
    require(
      accounts[referrer].isRegistered == true,
      "Referrer should be registered"
    );
    require(!accounts[msg.sender].isRegistered, "Address already registered");
    require(referrer != address(0), "Referrer cannot be 0x0 address");

    Account storage userAccount = accounts[msg.sender];
    userAccount.referrer = referrer;
    userAccount.isRegistered = true;
    userAccount.rank = Rank.Newbie;

    uint256 restAmount = msg.value;
    Account storage _currentUser = userAccount;
    // distribute registration fee to referrer 3 levels up, global omzet, dev team, admin
    for (uint256 i = 0; i < 10; i++) {
      address _parent = _currentUser.referrer;
      Account storage _parentAccount = accounts[_currentUser.referrer];

      if (_parent == address(0)) {
        break;
      }

      // LEVEL 1 upline got 40% of the registration fee
      if (i == 0) {
        rewards[_parent] = rewards[_parent].add(rewardValues.lvl1);
        restAmount = restAmount.sub(rewardValues.lvl1);
        emit RewardGiven(msg.sender, _parent, rewardValues.lvl1);
      }

      if (i == 1) {
        // LEVEL 2 got 10%
        rewards[_parent] = rewards[_parent].add(rewardValues.lvl2);
        restAmount = restAmount.sub(rewardValues.lvl2);
        emit RewardGiven(msg.sender, _parent, rewardValues.lvl2);
      }

      if (i == 2) {
        // LEVEL 3 got 5%
        rewards[_parent] = rewards[_parent].add(rewardValues.lvl3);
        restAmount = restAmount.sub(rewardValues.lvl3);
        emit RewardGiven(msg.sender, _parent, rewardValues.lvl3);
      }

      // increment total referred account
      // adjust rank
      _parentAccount.downlineCount = _parentAccount.downlineCount.add(1);
      if (
        _parentAccount.downlineCount >= 50 &&
        _parentAccount.downlineCount < 250 &&
        _parentAccount.rank != Rank.Rare
      ) {
        _parentAccount.rank = Rank.Rare;
        _parentAccount.rankUpdatedAt = block.timestamp;
        state.rareRankCount = state.rareRankCount.add(1);
      }

      if (
        _parentAccount.downlineCount >= 250 &&
        _parentAccount.downlineCount < 1000 &&
        _parentAccount.rank != Rank.SuperRare
      ) {
        _parentAccount.rank = Rank.SuperRare;
        _parentAccount.rankUpdatedAt = block.timestamp;
        state.rareRankCount = state.rareRankCount.sub(1);
        state.superRareRankCount = state.superRareRankCount.add(1);
      }

      if (
        _parentAccount.downlineCount >= 1000 &&
        _parentAccount.downlineCount < 3000 &&
        _parentAccount.rank != Rank.Epic
      ) {
        _parentAccount.rank = Rank.Epic;
        _parentAccount.rankUpdatedAt = block.timestamp;
        state.superRareRankCount = state.superRareRankCount.sub(1);
        state.epicRankCount = state.epicRankCount.add(1);
      }

      if (
        _parentAccount.downlineCount >= 3000 &&
        _parentAccount.downlineCount < 6000 &&
        _parentAccount.rank != Rank.Legend
      ) {
        _parentAccount.rank = Rank.Legend;
        _parentAccount.rankUpdatedAt = block.timestamp;
        state.epicRankCount = state.epicRankCount.sub(1);
        state.legendRankCount = state.legendRankCount.add(1);
      }

      if (
        _parentAccount.downlineCount >= 6000 &&
        _parentAccount.rank != Rank.SuperLegend
      ) {
        _parentAccount.rank = Rank.SuperLegend;
        _parentAccount.rankUpdatedAt = block.timestamp;
        state.legendRankCount = state.legendRankCount.sub(1);
        state.superLegendRankCount = state.superLegendRankCount.add(1);
      }

      _currentUser = _parentAccount;
    }

    // nft sales 25%
    // UPDATED: NFT sales pool 25% - send directly to feeReceiver
    if (rewardValues.nftSales > 0) {
      payable(addressList.feeReceiver).transfer(rewardValues.nftSales);
      restAmount = restAmount.sub(rewardValues.nftSales);
      emit NftSalesRewardPaid(addressList.feeReceiver, rewardValues.nftSales);
    }

    // REMOVED: global omzet is now 0%, so no need to store
    // storeGlobalOmzetReward();
    // restAmount = restAmount.sub(rewardValues.globalOmzet);

    // the rest percentage goes to admin / petmoon
    rewards[addressList.admin] = rewards[addressList.admin].add(restAmount);
    emit RewardGiven(msg.sender, addressList.admin, restAmount);
    emit Registration(msg.sender, referrer);
    return true;
  }

  function setLeaderStatus(address _address, bool _isLeader) public onlyOwner {
    accounts[_address].isLeader = _isLeader;
    emit LeaderStatusChanged(_address, _isLeader);
  }

  // this function to make force address
  function forceReferrer(
    address _newReferrer,
    address _userAddress
  ) public onlyOwner {
    // update setup referrer to new address
    Account storage userAccount = accounts[_userAddress];
    userAccount.referrer = _newReferrer;
  }

  function transferAccount(address _from, address _to) public onlyOwner {
    Account storage userAccount = accounts[_from];

    // Transfer semua data account ke address baru
    Account storage toAccount = accounts[_to];
    toAccount.rank = userAccount.rank;
    toAccount.isRegistered = userAccount.isRegistered;
    toAccount.referrer = userAccount.referrer;
    toAccount.downlineCount = userAccount.downlineCount;
    toAccount.nftSalesCount = userAccount.nftSalesCount;
    toAccount.rankUpdatedAt = userAccount.rankUpdatedAt;
    toAccount.rankRewardClaimedAt = userAccount.rankRewardClaimedAt;
    toAccount.isLeader = userAccount.isLeader;
    toAccount.omzet = userAccount.omzet;

    // Reset data account lama
    userAccount.rank = Rank.Newbie;
    userAccount.isRegistered = false;
    userAccount.referrer = address(0);
    userAccount.downlineCount = 0;
    userAccount.nftSalesCount = 0;
    userAccount.rankUpdatedAt = 0;
    userAccount.rankRewardClaimedAt = 0;
    userAccount.isLeader = false;
    userAccount.omzet = 0; // TAMBAHAN: Reset omzet

    // Transfer rewards
    uint currentReward = rewards[_from];
    rewards[_to] = currentReward;
    rewards[_from] = 0;

    emit AccountTransferred(_from, _to);
  }
}
