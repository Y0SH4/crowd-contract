// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "./CrowdNetwork.sol";

struct Card {
  bool isFarming;
  uint256 max;
  uint256 minted;
  uint256 price;
  uint256 upperPrice;
}

struct FarmingCard {
  uint256 percentage;
  uint256 lastFarm;
}

contract NftContract is
  Initializable,
  ERC721Upgradeable,
  ERC721EnumerableUpgradeable,
  ERC721URIStorageUpgradeable,
  OwnableUpgradeable,
  UUPSUpgradeable
{
  using CountersUpgradeable for CountersUpgradeable.Counter;
  CountersUpgradeable.Counter private _tokenIdCounter;
  ERC20 public currency;
  CrowdNetwork public netref;
  address public adminAddress;
  address public developer2;
  mapping(int8 => PoolReward) public poolRewards;
  mapping(string => Card) public cards;
  mapping(uint256 => FarmingCard) public farmingCard;
  uint256 public randNonce;
  mapping(address => uint256) public buyReward;
  mapping(address => uint256) public farmReward;
  uint256 private reservedBalance;
  mapping(address => uint256) public rankRewardClaimedAt;
  bool public isRankRewardClaimable;
  uint256 public rankRewardClaimOpenedAt;
  mapping(address => uint256) public totalNftValueMap;

  event MatchingBonusDistributed(
    address indexed farmer,
    address indexed referrer,
    uint8 level,
    uint256 amount
  );

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}

  function initialize(
    ERC20 _currency,
    CrowdNetwork _netref,
    address newAdminAddress,
    address _developer2
  ) public initializer {
    __ERC721_init("NFTNetwork", "NFT");
    __ERC721Enumerable_init();
    __ERC721URIStorage_init();
    __Ownable_init();
    __UUPSUpgradeable_init();
    currency = _currency;
    netref = _netref;
    adminAddress = newAdminAddress;
    developer2 = _developer2;
  }

  function safeMint(address to, string memory uri) public onlyOwner {
    uint256 tokenId = _tokenIdCounter.current();
    _tokenIdCounter.increment();
    _safeMint(to, tokenId);
    _setTokenURI(tokenId, uri);
  }

  function _authorizeUpgrade(
    address newImplementation
  ) internal override onlyOwner {}

  // The following functions are overrides required by Solidity.
  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 tokenId,
    uint256 batchSize
  ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
    require(!isRankRewardClaimable, "Transfer closed");
    super._beforeTokenTransfer(from, to, tokenId, batchSize);
  }

  function _burn(
    uint256 tokenId
  ) internal override(ERC721Upgradeable, ERC721URIStorageUpgradeable) {
    super._burn(tokenId);
  }

  function tokenURI(
    uint256 tokenId
  )
    public
    view
    override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
    returns (string memory)
  {
    return super.tokenURI(tokenId);
  }

  function supportsInterface(
    bytes4 interfaceId
  )
    public
    view
    override(
      ERC721EnumerableUpgradeable,
      ERC721URIStorageUpgradeable,
      ERC721Upgradeable
    )
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }

  function transferValueMap(address from, address to) public onlyOwner {
    uint256 lasAccoutn = totalNftValueMap[from];
    totalNftValueMap[to] += lasAccoutn;
    totalNftValueMap[from] = 0;
  }

  function _isMatchingQualified(
    address referrer,
    uint8 level
  ) private view returns (bool) {
    if (referrer == address(0)) {
      return false;
    }

    Rank rank;
    bool isLeader;
    uint256 nftBalance;
    (, , , , , , , isLeader) = netref.accounts(referrer);
    nftBalance = balanceOf(referrer);
    (rank, , , , , , , ) = netref.accounts(referrer);

    // Jika adalah leader, langsung qualified untuk 10 level
    if (isLeader) {
      return true;
    }

    // Non-leader harus punya NFT minimal
    if (nftBalance == 0) {
      return false;
    }

    // Level 1-5: Cukup punya NFT
    if (level < 5) {
      return true;
    }

    // Level 6-10: Harus punya NFT + minimal rank Rare
    return rank != Rank.Newbie;
  }

  function claimBuyReward() public {
    require(buyReward[msg.sender] > 0, "No Reward");
    uint256 rewardValue = buyReward[msg.sender];
    buyReward[msg.sender] = 0;
    reservedBalance = reservedBalance - rewardValue;
    currency.transfer(msg.sender, rewardValue);
  }

  function claimFarmReward() public {
    require(farmReward[msg.sender] > 0, "No Reward");
    uint256 rewardValue = farmReward[msg.sender];
    farmReward[msg.sender] = 0;
    reservedBalance = reservedBalance - rewardValue;
    currency.transfer(msg.sender, rewardValue);
  }

  function _random(uint256 modulus) private returns (uint256) {
    randNonce++;
    return
      uint256(
        keccak256(abi.encodePacked(block.timestamp, msg.sender, randNonce))
      ) % modulus;
  }

  function storeGlobalOmzet(uint256 value) private {
    PoolReward storage globalOmzet = poolRewards[0];
    globalOmzet.claimable = globalOmzet.claimable + value;
    reservedBalance = reservedBalance + value;
  }

  function getPoolReward() public view returns (uint256) {
    uint256 balance = currency.balanceOf(address(this));
    if (balance > reservedBalance) {
      return balance - reservedBalance;
    }

    return 0;
  }

  function getGlobalOmzet() public view returns (PoolReward memory) {
    return poolRewards[0];
  }

  function getMyRankReward() public view returns (uint256) {
    Rank rank;
    (rank, , , , , , , ) = netref.accounts(msg.sender);
    if (rankRewardClaimedAt[msg.sender] >= rankRewardClaimOpenedAt) {
      return 0;
    }

    if (rank == Rank.Newbie) {
      return 0;
    }

    if (rank == Rank.Rare) {
      PoolReward storage rareReward = poolRewards[1];
      return rareReward.claimable / netref.getTotalRareCount();
    }

    if (rank == Rank.SuperRare) {
      PoolReward storage superRareReward = poolRewards[2];
      return superRareReward.claimable / netref.getTotalSuperRareCount();
    }

    if (rank == Rank.Epic) {
      PoolReward storage epicReward = poolRewards[3];
      return epicReward.claimable / netref.getTotalEpicCount();
    }

    if (rank == Rank.Legend) {
      PoolReward storage legendReward = poolRewards[4];
      return legendReward.claimable / netref.getTotalLegendCount();
    }

    if (rank == Rank.SuperLegend) {
      PoolReward storage superLegendReward = poolRewards[5];
      return superLegendReward.claimable / netref.getTotalSuperLegendCount();
    }

    return 0;
  }

  function claimRankReward() public {
    Rank rank;
    (rank, , , , , , , ) = netref.accounts(msg.sender);
    require(rank != Rank.Newbie, "not eligible");
    require(
      rankRewardClaimedAt[msg.sender] < rankRewardClaimOpenedAt,
      "Reward already claimed"
    );
    uint256 rewardAmount = getMyRankReward();
    PoolReward storage globalOmzet = poolRewards[0];
    address feeReceiver;
    (, , , , feeReceiver) = netref.addressList();
    uint256 totalNftValue = totalNftValueMap[msg.sender];

    if (rank == Rank.Rare) {
      require(totalNftValue >= 100_000_000_000_000, "Not Enough NFT");
      PoolReward storage rareReward = poolRewards[1];
      if (rareReward.valueLeft < rewardAmount) {
        rewardAmount = rareReward.valueLeft;
      }
      uint256 tenPercent = (rewardAmount * 10) / 100;
      currency.transfer(feeReceiver, tenPercent);
      rewardAmount = rewardAmount - tenPercent;

      currency.transfer(msg.sender, rewardAmount);
      rewardAmount = rewardAmount + tenPercent;
      rareReward.valueLeft = rareReward.valueLeft - rewardAmount;
    }

    if (rank == Rank.SuperRare) {
      require(totalNftValue >= 500_000_000_000_000, "Not Enough NFT");
      PoolReward storage superRareReward = poolRewards[2];
      if (superRareReward.valueLeft < rewardAmount) {
        rewardAmount = superRareReward.valueLeft;
      }

      uint256 tenPercent = (rewardAmount * 10) / 100;
      currency.transfer(feeReceiver, tenPercent);
      rewardAmount = rewardAmount - tenPercent;

      currency.transfer(msg.sender, rewardAmount);
      rewardAmount = rewardAmount + tenPercent;
      superRareReward.valueLeft = superRareReward.valueLeft - rewardAmount;
    }

    if (rank == Rank.Epic) {
      require(totalNftValue >= 2_000_000_000_000_000, "Not Enough NFT");
      PoolReward storage epicReward = poolRewards[3];
      if (epicReward.valueLeft < rewardAmount) {
        rewardAmount = epicReward.valueLeft;
      }

      uint256 tenPercent = (rewardAmount * 10) / 100;
      currency.transfer(feeReceiver, tenPercent);
      rewardAmount = rewardAmount - tenPercent;

      currency.transfer(msg.sender, rewardAmount);
      rewardAmount = rewardAmount + tenPercent;
      epicReward.valueLeft = epicReward.valueLeft - rewardAmount;
    }

    if (rank == Rank.Legend) {
      require(totalNftValue >= 6_000_000_000_000_000, "Not Enough NFT");
      PoolReward storage legendReward = poolRewards[4];
      if (legendReward.valueLeft < rewardAmount) {
        rewardAmount = legendReward.valueLeft;
      }

      uint256 tenPercent = (rewardAmount * 10) / 100;
      currency.transfer(feeReceiver, tenPercent);
      rewardAmount = rewardAmount - tenPercent;

      currency.transfer(msg.sender, rewardAmount);
      rewardAmount = rewardAmount + tenPercent;
      legendReward.valueLeft = legendReward.valueLeft - rewardAmount;
    }

    if (rank == Rank.SuperLegend) {
      require(totalNftValue >= 12_000_000_000_000_000, "Not Enough NFT");
      PoolReward storage superLegendReward = poolRewards[5];
      if (superLegendReward.valueLeft < rewardAmount) {
        rewardAmount = superLegendReward.valueLeft;
      }

      uint256 tenPercent = (rewardAmount * 10) / 100;
      currency.transfer(feeReceiver, tenPercent);
      rewardAmount = rewardAmount - tenPercent;

      currency.transfer(msg.sender, rewardAmount);
      rewardAmount = rewardAmount + tenPercent;
      superLegendReward.valueLeft = superLegendReward.valueLeft - rewardAmount;
    }

    rankRewardClaimedAt[msg.sender] = block.timestamp;
    globalOmzet.valueLeft = globalOmzet.valueLeft - rewardAmount;
    reservedBalance = reservedBalance - rewardAmount;
  }

  function startClaimingRankRewards() public onlyOwner {
    require(!isRankRewardClaimable, "already started");

    isRankRewardClaimable = true;
    rankRewardClaimOpenedAt = block.timestamp;

    PoolReward storage globalOmzet = poolRewards[0];
    globalOmzet.valueLeft = globalOmzet.claimable;
    globalOmzet.claimable = globalOmzet.claimable - globalOmzet.valueLeft;

    uint256 valueLeft = globalOmzet.valueLeft;

    // Rare Pool
    PoolReward storage rareReward = poolRewards[1];
    // 12.85714286%
    rareReward.valueLeft = (globalOmzet.valueLeft * 1285714286) / 10000000000;
    rareReward.claimable = rareReward.valueLeft;
    valueLeft = valueLeft - rareReward.valueLeft;

    // Super Rare Pool
    PoolReward storage superRareReward = poolRewards[2];
    // 18.57142857%
    superRareReward.valueLeft =
      (globalOmzet.valueLeft * 1857142857) / 10000000000;
    superRareReward.claimable = superRareReward.valueLeft;
    valueLeft = valueLeft - superRareReward.valueLeft;

    // Epic Pool
    PoolReward storage epicReward = poolRewards[3];
    // 21.42857134%
    epicReward.valueLeft = (globalOmzet.valueLeft * 2142857134) / 10000000000;
    epicReward.claimable = epicReward.valueLeft;
    valueLeft = valueLeft - epicReward.valueLeft;

    // Legend Pool
    PoolReward storage legendReward = poolRewards[4];
    // 22.85714286%
    legendReward.valueLeft = (globalOmzet.valueLeft * 2285714286) / 10000000000;
    legendReward.claimable = legendReward.valueLeft;
    valueLeft = valueLeft - legendReward.valueLeft;

    // SuperLegend Pool
    PoolReward storage superLegendReward = poolRewards[5];
    // 24.28571429%
    superLegendReward.valueLeft = valueLeft;
    superLegendReward.claimable = superLegendReward.valueLeft;
  }

  function stopClaimingRankRewards() public onlyOwner {
    require(isRankRewardClaimable, "not yet started");

    isRankRewardClaimable = false;

    PoolReward storage globalOmzet = poolRewards[0];
    globalOmzet.claimable = globalOmzet.claimable + globalOmzet.valueLeft;
    globalOmzet.valueLeft = 0;

    // Rare Pool
    PoolReward storage rareReward = poolRewards[1];
    rareReward.valueLeft = 0;
    rareReward.claimable = 0;

    // Super Rare Pool
    PoolReward storage superRareReward = poolRewards[2];
    superRareReward.valueLeft = 0;
    superRareReward.claimable = 0;

    // Epic Pool
    PoolReward storage epicReward = poolRewards[3];
    epicReward.valueLeft = 0;
    epicReward.claimable = 0;

    // Legend Pool
    PoolReward storage legendReward = poolRewards[4];
    legendReward.valueLeft = 0;
    legendReward.claimable = 0;

    // SuperLegend Pool
    PoolReward storage superLegendReward = poolRewards[5];
    superLegendReward.valueLeft = 0;
    superLegendReward.claimable = 0;
  }

  function getFarmValue(uint256 tokenId) public view returns (uint256) {
    string memory hash = tokenURI(tokenId);
    Card storage _card = cards[hash];
    require(_card.isFarming, "Card is not a farming card");

    uint256 rewardPercentage = farmingCard[tokenId].percentage;
    uint256 baseReward = (_card.price * rewardPercentage) / 1000;

    require(getPoolReward() >= baseReward, "Not enough reward");

    uint256 lastFarm = farmingCard[tokenId].lastFarm;
    uint256 rewardPerSec = baseReward / 86400;
    uint256 farmValue = (block.timestamp - lastFarm) * rewardPerSec;
    return farmValue;
  }

  function farm(uint256 tokenId) public returns (bool) {
    string memory hash = tokenURI(tokenId);
    Card storage _card = cards[hash];
    require(_card.isFarming, "Card is not a farming card");
    require(ownerOf(tokenId) == msg.sender, "caller is not owner");

    uint256 reward = getFarmValue(tokenId);
    farmingCard[tokenId].lastFarm = block.timestamp;
    uint256 uplineReward = (reward / 2) / 10;

    require(getPoolReward() >= reward, "Not enough reward");
    uint256 balanceLeftForUpline = getPoolReward() - reward;

    address referrer;
    Rank rank;
    (rank, , referrer, , , , , ) = netref.accounts(msg.sender);

    for (uint8 i = 0; i < 10; i++) {
      if (referrer == address(0)) {
        break;
      }

      if (balanceLeftForUpline < uplineReward) {
        break;
      }

      if (_isMatchingQualified(referrer, i)) {
        farmReward[referrer] += uplineReward;
        reservedBalance = reservedBalance + uplineReward;
        balanceLeftForUpline = balanceLeftForUpline - uplineReward;

        // Emit event untuk tracking
        emit MatchingBonusDistributed(
          msg.sender,
          referrer,
          i + 1,
          uplineReward
        );
      }

      (, , referrer, , , , , ) = netref.accounts(referrer);
    }

    currency.transfer(msg.sender, reward);
    return true;
  }

  function buyCard(string memory hash) public {
    require(!isRankRewardClaimable, "Minting closed");
    require(cards[hash].max > 0, "Card doesn't exists");
    require(cards[hash].minted < cards[hash].max, "Card is already sold out");

    Card storage _card = cards[hash];
    _card.minted = _card.minted + 1;
    uint256 bumper;
    uint256 price = _card.price;
    uint256 valueLeft = price;
    address referrer;
    bool isRegistered;
    (, isRegistered, referrer, , , , , ) = netref.accounts(msg.sender);

    if (!isRegistered) {
      bumper = _card.upperPrice - price;
    }

    currency.transferFrom(msg.sender, address(this), price + bumper);

    for (uint8 i = 0; i < 3; i++) {
      if (referrer == address(0)) {
        break;
      }

      if (i == 0) {
        // upper level 1
        uint256 insentif = (price * 8) / 100;
        valueLeft = valueLeft - insentif;
        buyReward[referrer] += insentif;
        reservedBalance = reservedBalance + insentif;
      }

      if (i == 1) {
        // upper level 2
        uint256 insentif = (price * 3) / 100;
        valueLeft = valueLeft - insentif;
        buyReward[referrer] += insentif;
        reservedBalance = reservedBalance + insentif;
      }

      if (i == 2) {
        // upper level 3
        uint256 insentif = (price * 2) / 100;
        valueLeft = valueLeft - insentif;
        buyReward[referrer] += insentif;
        reservedBalance = reservedBalance + insentif;
      }

      (, isRegistered, referrer, , , , , ) = netref.accounts(referrer);
    }

    // value for developer
    uint256 developerVal = (price * 10) / 100;
    valueLeft = valueLeft - developerVal;
    reservedBalance = reservedBalance + developerVal;
    buyReward[adminAddress] += developerVal + bumper;
    totalNftValueMap[msg.sender] += _card.price;

    // store global omzet value 17%
    uint256 globalOmzetVal = (price * 17) / 100;
    storeGlobalOmzet(globalOmzetVal);

    //================================= Developer 2 =======================
    uint256 developer2Val = (price * 10) / 100;
    buyReward[developer2] += developer2Val;
    reservedBalance = reservedBalance + developer2Val;

    uint256 tokenId = _tokenIdCounter.current();

    // apply random farming reward percentage
    if (_card.isFarming) {
      farmingCard[tokenId].lastFarm = block.timestamp;
      uint256 rand = _random(100); // 0 - 99
      if (rand >= 0 && rand <= 59) {
        farmingCard[tokenId].percentage = 7;
      }
      if (rand > 59 && rand <= 88) {
        farmingCard[tokenId].percentage = 8;
      }
      if (rand > 88 && rand <= 96) {
        farmingCard[tokenId].percentage = 9;
      }
      if (rand > 96 && rand <= 98) {
        farmingCard[tokenId].percentage = 10;
      }
      if (rand == 99) {
        farmingCard[tokenId].percentage = 15;
      }
    }

    _tokenIdCounter.increment();
    _safeMint(msg.sender, tokenId);
    _setTokenURI(tokenId, hash);
  }

  function updateCard(
    string memory hash,
    uint256 max,
    uint256 price
  ) public onlyOwner {
    uint256 bumper = (price * 20) / 100;

    cards[hash].max = max;
    cards[hash].price = price;
    cards[hash].upperPrice = price + bumper;
  }

  function setCard(
    string memory hash,
    uint256 max,
    uint256 price,
    bool isFarming
  ) public onlyOwner {
    require(cards[hash].max == 0, "Card already exists");
    require(max > 0, "Max should be more than zero");
    uint256 bumper = (price * 20) / 100;

    cards[hash] = Card({
      isFarming: isFarming,
      max: max,
      price: price,
      upperPrice: price + bumper,
      minted: 0
    });
  }

  function _afterTokenTransfer(
    address from,
    address to,
    uint256 tokenId,
    uint256 batchSize
  ) internal virtual override {
    super._afterTokenTransfer(from, to, tokenId, batchSize);
    uint256 price = cards[tokenURI(tokenId)].price;
    if (from == address(0)) {
      totalNftValueMap[to] += price;
    } else if (to == address(0)) {
      totalNftValueMap[from] -= price;
    } else {
      totalNftValueMap[from] -= price;
      totalNftValueMap[to] += price;
    }
  }

  function changeAdmin(address _newAdminAddress) public onlyOwner {
    // get old admin state
    address prevAdminAddress = adminAddress;
    uint prevBuyReward = buyReward[prevAdminAddress];

    // set new admin address
    adminAddress = _newAdminAddress;
    buyReward[_newAdminAddress] = prevBuyReward;

    // reset old adminAddres
    buyReward[prevAdminAddress] = 0;
  }
}
