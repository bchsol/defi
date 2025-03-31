// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Lending {
    IERC20 public immutable token; // 담보로 사용할 ERC20 토큰
    uint public interestRate; // 이자율 (예: 5% = 500 basis points)
    uint public loanDuration; // 대출 기간 (초 단위)
    
    struct Loan {
        uint collateralAmount;
        uint loanAmount;
        uint interest;
        uint dueDate;
        bool repaid;
    }

    mapping(address => Loan) public loans;

    constructor(address _token, uint _interestRate, uint _loanDuration) {
        token = IERC20(_token);
        interestRate = _interestRate;
        loanDuration = _loanDuration;
    }

    // 담보를 예치하고 대출받기
    function depositCollateralAndBorrow(uint _collateralAmount, uint _loanAmount) external {
        require(loans[msg.sender].loanAmount == 0, "Existing loan must be repaid");
        require(_collateralAmount >= _loanAmount, "Not enough collateral");
        
        token.transferFrom(msg.sender, address(this), _collateralAmount);
        
        uint interest = (_loanAmount * interestRate) / 10000;
        uint dueDate = block.timestamp + loanDuration;

        loans[msg.sender] = Loan({
            collateralAmount: _collateralAmount,
            loanAmount: _loanAmount,
            interest: interest,
            dueDate: dueDate,
            repaid: false
        });

        // 대출금은 msg.sender에게 전달 (별도의 대출 토큰 사용 가능)
        payable(msg.sender).transfer(_loanAmount);
    }

    // 대출 상환
    function repayLoan() external payable {
        Loan storage loan = loans[msg.sender];
        require(loan.loanAmount > 0, "No active loan");
        require(block.timestamp <= loan.dueDate, "Loan is overdue");
        require(msg.value == loan.loanAmount + loan.interest, "Incorrect repayment amount");

        loan.repaid = true;

        // 담보 반환
        token.transfer(msg.sender, loan.collateralAmount);
    }

    // 대출이 연체된 경우 담보 청산
    function liquidateLoan(address _borrower) external {
        Loan storage loan = loans[_borrower];
        require(loan.loanAmount > 0, "No active loan");
        require(block.timestamp > loan.dueDate, "Loan is not overdue");
        require(!loan.repaid, "Loan already repaid");

        // 담보 청산
        token.transfer(msg.sender, loan.collateralAmount);
        delete loans[_borrower];
    }
}
