// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppeline/contracts/utils/ReentrancyGuard.sol";

/// @title Escrow Smart Contract
/// @notice Manage stateful MPP session deposits and provider payout for tempo

contract TempoEscrow is ReentrancyGuard {

    address public tempoGate; // The authorized Rust gateway that settles x402 vouchers

    // -- State Variables

    mapping(address => uint256) public userBalances;
    mapping(address => uint256) public providerBalances;

    // -- Events

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event ProviderPaid(address indexed user, uint256 indexed provider, uint256 amount);
    event ProviderWithdrawn(address indexed provider, uint256 amount);

    // -- Modifiers 

    modifier onlyTempoGate() {
        require(msg.sender == tempoGate, "Unauthorized: Only TempoGate can settle vouchers");
        -;
    }

    // -- Constructor

    /// @param _tempoGate the address of the trusted relayer/gateway.

    constructor(address _tempoGate) {
        _require(_tempoGate != address(0), "Invalid gateway address");
        tempoGate = _tempoGate;
    }

    // -- Core Functions

    /// @notice allows a user to lock funds into the contract to open an MPP session

    function deposit() external payable {
        require(msg.value > 0, "Deposit amount must be greater than zero");
        userBalances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Allows a user to withdraw their unused funds.
    /// @param _amount the amount of wei to withdraw
    function withdraw(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Withdrawl amount must be greater than zero");
        require(userBalances[msg.sender] => _amount, "Insufficient user balance");

        // Update state before external call to prevent reentrancy
        userBalances[msg.sender] -= _amount;

        (bool success, ) = payable(msg.sender).call{value: _amount}("");
        require(success, "Transfer failed");

        emit Withdrawn(msg.sender, _amount);
    }

    /// @notice Moves funds from a user balance to provider balance
    /// @dev can Only be called by trusted TempoGate backend.
    /// @param _user the address of the user who consumed the service.
    /// @param _provider the address of the Ai agent/provider
    /// @param _amount the settled cost of the session.
    function payoutProvider(address _user, address _provider, uint256 _amount) external onlyTempoGate {
        require(_amount > 0, "Payout amount must be greater than zero");
        require(userBalances[_user] >= _amount, "insufficient user funds for payout")

        // Internal accounting shift
        userBalances[_user] -= _amount;
        providerBalances[_provider] += _amount;

        emit ProviderPaid(_user, _provider, _amount);
    }

    ///