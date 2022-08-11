// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITRC20 {
    event Transfer( address indexed from, address indexed to, uint256 value);
    event Approval( address indexed owner, address indexed spender, uint256 value);
    function totalSupply() external view returns (uint256);
    function balanceOf( address account) external view returns (uint256);
    function transfer( address to, uint256 amount) external returns (bool);
    function allowance( address owner, address spender) external view returns (uint256);
    function transferFrom( address from, address to, uint256 amount ) external returns (bool);
}

interface ITRC165 {
  function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface ITRC721 is ITRC165 {
  event Transfer( address indexed from, address indexed to, uint256 indexed tokenId);
  event Approval( address indexed owner, address indexed approved, uint256 indexed tokenId);
  event ApprovalForAll( address indexed owner, address indexed operator, bool approved);

  function balanceOf( address owner) external view returns (uint256 balance);
  function ownerOf(uint256 tokenId) external view returns ( address owner);
  function safeTransferFrom( address from, address to, uint256 tokenId, bytes calldata data ) external;
  function safeTransferFrom( address from, address to, uint256 tokenId ) external;
  function transferFrom( address from, address to, uint256 tokenId ) external;
  function approve( address to, uint256 tokenId) external;
  function setApprovalForAll( address operator, bool _approved) external;
  function getApproved(uint256 tokenId) external view returns ( address operator);
  function isApprovedForAll( address owner, address operator) external view returns (bool);
}

interface ERC721TokenReceiver {
  function onERC721Received(address _operator, address _from, uint256 _tokenId, bytes calldata _data) external returns(bytes4);
}

interface TRC721TokenReceiver {
  function onTRC721Received(address _operator, address _from, uint256 _tokenId, bytes calldata _data) external returns(bytes4);
}

contract Ownable {
  address private _owner;

  constructor () {
    _owner = msg.sender;
  }

  function owner() public view returns ( address) {
    return _owner;
  }

  modifier onlyOwner() {
    require(owner() == msg.sender, "Ownable: Caller not Owner");
    _;
  }
}

contract CubieStacking is Ownable, TRC721TokenReceiver {

  ITRC20 public immutable TOKEN_CONTRACT;
  ITRC721 public immutable NFT_CONTRACT;

  uint256 internal dailyReward = 10 * 1e8;
  uint256 public stakeOn = 1;
  uint256 internal stake_stoped_at = 0;

  event CubieStaked( address indexed owner, uint256 tokenId, uint256 value);
  event CubieUnstaked( address indexed owner, uint256 tokenId, uint256 value);
  event RewardClaimed( address owner, uint256 reward);

  constructor( address payable _NFT_CONTRACT, address payable _TOKEN_CONTRACT) payable {
    NFT_CONTRACT = ITRC721(_NFT_CONTRACT);
    TOKEN_CONTRACT = ITRC20(_TOKEN_CONTRACT);
  }

  struct Stake {
    address owner;
    uint256 tokenId;
    uint256 timestamp;
    uint256 power;
  }

  mapping(uint256 => Stake) public vault;
  mapping(address => uint256[]) private userStacks;
  mapping(uint256 => uint256) public hasPaid;

  function setDailyReward(uint256 value) public onlyOwner {
    dailyReward = value * 1e8;
  }

  function getDailyReward() public view returns(uint256) {
    return dailyReward;
  }

  function _tokensOfOwner() public view returns (uint256[] memory){
    return _tokensOfOwner(msg.sender);
  }

  function _tokensOfOwner(address owner) public view returns (uint256[] memory) {
    return userStacks[owner];
  }

  function stake(uint256 tokenId, uint256 power) external payable {
    require(NFT_CONTRACT.ownerOf(tokenId) == msg.sender, "Not yours");
    require(vault[tokenId].tokenId == 0, "Only stake once");
    require(power < 2, "Invalid");
    require(stakeOn, "Paused or Ended");


    NFT_CONTRACT.safeTransferFrom(msg.sender, address(this), tokenId);
    emit CubieStaked(msg.sender, tokenId, block.timestamp);
    vault[tokenId] = Stake({
      tokenId: tokenId,
      timestamp: block.timestamp,
      owner: msg.sender,
      power: power
    });
    userStacks[msg.sender].push(tokenId);
    hasPaid[tokenId] = 0;
  }

  function unstake(uint256 tokenId) internal {
    require(NFT_CONTRACT.ownerOf(tokenId) == address(this), "Not staked");

    NFT_CONTRACT.safeTransferFrom(address(this), msg.sender, tokenId);
    emit CubieUnstaked(msg.sender, tokenId, block.timestamp);

    delete vault[tokenId];
    delete hasPaid[tokenId];
    // delete userStacks[msg.sender][tokenId];
  }

  function earnings(uint256 tokenId) public view returns(uint256) {
    Stake memory staked = vault[tokenId];
    require(staked.owner == msg.sender, "Not yours");
    require((staked.timestamp + 10 minutes) < block.timestamp, "Must stake for 24 hrs");
    require(stakeOn, "Paused or Ended");

    uint256 earned = getDailyReward() * ((block.timestamp - staked.timestamp)/(10 minutes));
    uint256 toPay = (earned - hasPaid[tokenId]);

    if (toPay > 0) return toPay;
    else return earned;
  }

  function claim(uint256 tokenId, bool _unstake) external {
    address claimer = payable(msg.sender);
    uint256 earned = earnings(tokenId);

    if (earned > 0) {
      hasPaid[tokenId] += earned;
      bool success = TOKEN_CONTRACT.transfer(claimer, earned);
      require(success);
      emit RewardClaimed(claimer, earned);
    }
    if(_unstake){
      unstake(tokenId);
    }
  }

  function withdrawBalance(address payable _to) public onlyOwner returns(uint256) {
    uint256 contract_balance = TOKEN_CONTRACT.balanceOf(address(this));
    bool success = TOKEN_CONTRACT.transfer(_to, contract_balance);
    require(success);
    return contract_balance;
  }

  function stopStake() public onlyOwner {
    stakeOn = 0;
  }

  function restartStake() public onlyOwner {
    stakeOn = 1;
  }

  function onERC721Received( address, address, uint256, bytes memory )
  public virtual override returns (bytes4) { return this.onERC721Received.selector; }

  function onTRC721Received( address, address, uint256, bytes memory )
  public virtual override returns (bytes4) { return this.onTRC721Received.selector; }
}