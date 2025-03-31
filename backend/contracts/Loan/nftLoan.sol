// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// OpenZeppelin 인터페이스 및 보안 라이브러리 임포트
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol"; 
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title NFTCollateralLoan
 * @notice NFT를 담보로 토큰 대출을 제공하는 스마트 컨트랙트 예시 (동일 네트워크 검증 포함)
 */
contract NFTCollateralLoan is Ownable, ReentrancyGuard, IERC721Receiver {

    /// @notice 대출 정보를 저장하는 구조체
    struct Loan {
        uint256 loanId;         // 대출 고유 ID
        address borrower;       // 대출 신청자
        address nftAddress;     // 담보로 제공된 NFT 컨트랙트 주소
        uint256 tokenId;        // NFT 토큰 ID
        uint256 loanAmount;     // 대출받은 토큰 금액
        uint256 interestRate;   // 연이율(APR, basis points 단위 예: 500 = 5% APR)
        uint256 startTime;      // 대출 시작 시각 (타임스탬프)
        bool repaid;            // 상환 여부
        bool liquidated;        // 청산 여부
    }

    uint256 public loanCounter;
    mapping(uint256 => Loan) public loans;

    // 대출 파라미터
    // 예: maxLTV가 5000이면 NFT 플로어 프라이스의 50%까지 대출 가능 (basis points 단위)
    uint256 public maxLTV;
    // 청산 임계치 예: 7000 (70%)
    uint256 public liquidationThreshold;

    // NFT 컬렉션별 최저가 (플로어 프라이스)
    // 이 값은 오라클이나 관리자가 업데이트해야 합니다.
    mapping(address => uint256) public floorPrice;

    // 허용된 NFT 컬렉션 (동일 네트워크에서 운영되는 NFT만 허용)
    mapping(address => bool) public allowedNFT;

    // 대출에 사용되는 ERC20 토큰
    IERC20 public lendingToken;

    // 이벤트 정의
    event LoanCreated(
        uint256 indexed loanId,
        address indexed borrower,
        address nftAddress,
        uint256 tokenId,
        uint256 loanAmount,
        uint256 interestRate
    );
    event LoanRepaid(uint256 indexed loanId, address borrower, uint256 totalRepayment);
    event LoanLiquidated(uint256 indexed loanId, address liquidator);
    event AllowedNFTUpdated(address nftAddress, bool allowed);

    /**
     * @notice 생성자에서 대출에 사용될 토큰과 파라미터들을 설정합니다.
     * @param _lendingToken ERC20 토큰 주소
     * @param _maxLTV 최대 LTV (basis points, 예: 5000 = 50%)
     * @param _liquidationThreshold 청산 임계치 (basis points, 예: 7000 = 70%)
     */
    constructor(
        address _lendingToken, 
        uint256 _maxLTV, 
        uint256 _liquidationThreshold
    ) Ownable(msg.sender){
        require(_lendingToken != address(0), "Invalid token address");
        lendingToken = IERC20(_lendingToken);
        maxLTV = _maxLTV;
        liquidationThreshold = _liquidationThreshold;
    }

    /**
     * @notice NFT 컬렉션의 최저가(플로어 프라이스)를 업데이트합니다.
     *         (실제 구현에서는 오라클 연동을 고려해야 합니다.)
     * @param _nftAddress NFT 컨트랙트 주소
     * @param _price 최저가
     */
    function setFloorPrice(address _nftAddress, uint256 _price) external onlyOwner {
        floorPrice[_nftAddress] = _price;
    }

    /**
     * @notice NFT 컬렉션을 허용 목록에 추가합니다.
     * @param _nftAddress NFT 컨트랙트 주소
     */
    function addAllowedNFT(address _nftAddress) external onlyOwner {
        allowedNFT[_nftAddress] = true;
        emit AllowedNFTUpdated(_nftAddress, true);
    }

    /**
     * @notice NFT 컬렉션을 허용 목록에서 제거합니다.
     * @param _nftAddress NFT 컨트랙트 주소
     */
    function removeAllowedNFT(address _nftAddress) external onlyOwner {
        allowedNFT[_nftAddress] = false;
        emit AllowedNFTUpdated(_nftAddress, false);
    }

    /**
     * @notice 대출 신청: NFT를 담보로 토큰을 대출받습니다.
     * @param _nftAddress NFT 컨트랙트 주소
     * @param _tokenId 담보로 제공할 NFT 토큰 ID
     * @param _loanAmount 대출 받고자 하는 토큰 금액
     * @param _interestRate 연이율(APR, basis points) - 대출 시 결정
     */
    function createLoan(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _loanAmount,
        uint256 _interestRate
    ) external nonReentrant {
        // 동일 네트워크에서 운영되는 NFT만 허용
        require(allowedNFT[_nftAddress], "NFT not allowed on this network");

        uint256 nftFloor = floorPrice[_nftAddress];
        require(nftFloor > 0, "Floor price not set");

        // 최대 대출 가능 금액 = NFT 플로어 프라이스 * maxLTV / 10000
        uint256 maxLoanAllowed = (nftFloor * maxLTV) / 10000;
        require(_loanAmount <= maxLoanAllowed, "Loan amount exceeds maximum LTV");

        // NFT 소유권 확인 및 컨트랙트로 전송 (safeTransferFrom 사용)
        IERC721 nft = IERC721(_nftAddress);
        require(nft.ownerOf(_tokenId) == msg.sender, "Not the owner of NFT");
        nft.safeTransferFrom(msg.sender, address(this), _tokenId);

        // 컨트랙트에 대출할 토큰 잔고가 충분한지 확인
        require(lendingToken.balanceOf(address(this)) >= _loanAmount, "Insufficient liquidity");

        // 대출 토큰 전송
        lendingToken.transfer(msg.sender, _loanAmount);

        // 대출 정보 저장
        loanCounter++;
        loans[loanCounter] = Loan({
            loanId: loanCounter,
            borrower: msg.sender,
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            loanAmount: _loanAmount,
            interestRate: _interestRate,
            startTime: block.timestamp,
            repaid: false,
            liquidated: false
        });

        emit LoanCreated(loanCounter, msg.sender, _nftAddress, _tokenId, _loanAmount, _interestRate);
    }

    /**
     * @notice 대출 상환: 대출 원금과 이자를 상환하면 담보 NFT 반환
     *         이자 계산은 단순 이자 (APR) 기준으로 계산됩니다.
     * @param _loanId 상환할 대출의 ID
     */
    function repayLoan(uint256 _loanId) external nonReentrant {
        Loan storage loan = loans[_loanId];
        require(loan.borrower == msg.sender, "Not the borrower");
        require(!loan.repaid, "Loan already repaid");
        require(!loan.liquidated, "Loan already liquidated");

        uint256 duration = block.timestamp - loan.startTime;
        // 단순 이자 계산: 이자 = loanAmount * interestRate * duration / (365일 * 10000)
        uint256 interest = (loan.loanAmount * loan.interestRate * duration) / (365 days * 10000);
        uint256 totalRepayment = loan.loanAmount + interest;

        // 차입자로부터 상환 토큰 회수
        require(lendingToken.transferFrom(msg.sender, address(this), totalRepayment), "Token transfer failed");

        // 담보 NFT 반환
        IERC721 nft = IERC721(loan.nftAddress);
        nft.safeTransferFrom(address(this), msg.sender, loan.tokenId);

        loan.repaid = true;
        emit LoanRepaid(_loanId, msg.sender, totalRepayment);
    }

    /**
     * @notice 청산: NFT 플로어 프라이스 하락 등으로 현재 LTV가 청산 임계치 이상일 경우,
     *         누구나 청산하여 NFT를 획득할 수 있습니다.
     * @param _loanId 청산할 대출의 ID
     */
    function liquidateLoan(uint256 _loanId) external nonReentrant {
        Loan storage loan = loans[_loanId];
        require(!loan.repaid, "Loan already repaid");
        require(!loan.liquidated, "Loan already liquidated");

        uint256 nftFloor = floorPrice[loan.nftAddress];
        require(nftFloor > 0, "Floor price not set");

        // 현재 LTV 계산 (여기서는 원금만 기준, 필요시 이자 포함 고려 가능)
        uint256 currentLTV = (loan.loanAmount * 10000) / nftFloor; // basis points 단위

        require(currentLTV >= liquidationThreshold, "Loan not eligible for liquidation");

        // 청산 실행: 청산자가 NFT를 획득
        IERC721 nft = IERC721(loan.nftAddress);
        nft.safeTransferFrom(address(this), msg.sender, loan.tokenId);

        loan.liquidated = true;
        emit LoanLiquidated(_loanId, msg.sender);
    }

    /**
     * @notice 컨트랙트가 보유한 ERC20 토큰 출금 (관리자 전용)
     * @param _amount 출금할 토큰 금액
     */
    function withdrawTokens(uint256 _amount) external onlyOwner {
        require(lendingToken.balanceOf(address(this)) >= _amount, "Insufficient balance");
        lendingToken.transfer(msg.sender, _amount);
    }

    /**
     * @notice ERC721 안전 전송을 위해 구현 (IERC721Receiver 인터페이스)
     */
    function onERC721Received(
        address, /* operator */
        address, /* from */
        uint256, /* tokenId */
        bytes calldata /* data */
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
