// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Escrow Smart Contract
/// @notice Manage stateful MPP session deposits and provider payout for tempo

contract TempoEscrow is ReentrancyGuard {
    address public tempoGate; // The authorized Rust gateway that settles x402 vouchers

    // -- State Variables

    mapping(address => uint256) public userBalances;
    mapping(address => uint256) public providerBalances;

    struct Session {
        address user;
        address provider;
        uint256 allocatedAmount; // Max budget user authorize for this session
        uint256 spentAmount;
        bool isActive;
    }

    // sessionId maps to the session struct
    mapping(byte32 => Session) public sessions;

    // -- Events

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event SessionCreated(
        bytes32 indexed sessionId,
        address indexed user,
        address indexed provider,
        uint256 allocatedAmount
    );
    event SessionClosed(
        bytes32 indexed sessionId,
        uint256 unspentAmountReturned
    );
    event Settled(
        bytes32 indexed sessionId,
        address indexed provider,
        uint256 amount
    );
    event ProviderPaid(
        address indexed user,
        address indexed provider,
        uint256 amount
    );
    event ProviderWithdrawn(address indexed provider, uint256 amount);

    // -- Modifiers

    modifier OnlyTempoGate() {
        require(
            msg.sender == tempoGate,
            "Unauthorized: Only TempoGate can settle vouchers"
        );
        _;
    }

    // -- Constructor

    /// @param _tempoGate the address of the trusted relayer/gateway.

    constructor(address _tempoGate) {
        require(_tempoGate != address(0), "Invalid gateway address");
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
        require(
            userBalances[msg.sender] >= _amount,
            "Insufficient user balance"
        );

        // Update state before external call to prevent reentrancy
        userBalances[msg.sender] -= _amount;

        (bool success, ) = payable(msg.sender).call{value: _amount}("");
        require(success, "Transfer failed");

        emit Withdrawn(msg.sender, _amount);
    }

    // -- SESSION STORAGE

    /// @notice Opens a new MPP session, reserving a specific amount of the user's balance.
    /// @param _sessionId The unique identifier for the session.
    /// @param _provider The address of the AI agent/provider.
    /// @param _allocatedAmount The max budget locked for this session.

    function createSession(
        bytes32 _sessionId,
        address _provider,
        uint256 _allocatedAmount
    ) external onlyTempoGate {
        require(!sessions[_sessionId].isActive, "Session already exists");
        require(_allocateAmount > 0, "Allocation Must be > 0");
        require(
            userBalances[msg.sender] >= _allocatedAmount,
            "Insufficient user funds for payout"
        );

        // Internal accounting shift, locking funds until spent or returned.
        userBalances[msg.sender] -= _allocatedAmount;
        sessions[_sessionId] = Session({
            user: msg.sender,
            provider: _provider,
            allocatedAmount: _allocatedAmount,
            spentAmount: 0,
            isActive: true
        });

        emit SessionCreated(
            _sessionId,
            msg.sender,
            _provider,
            _allocatedAmount
        );
    }

    /// @notice Settles an x402 voucher, moving funds from the session to the provider.
    /// @dev Replaces payoutProvider. Can only be called by the trusted TempoGate backend.
    /// @param _sessionId The unique identifier for the active session.
    /// @param _amount The settled cost of the session iteration to pay the provider.

    function settle(byte32 _sessionId, uint256 _amount) external onlyTempoGate {
        Session storage session = sessions[_sessionId];
        require(session.isActive, "Session is not active");
        require(_amount > 0, "Settle amount must be > 0");
        require(
            session.spentAmount + _amount <= session.allocatedAmount,
            "Exceeded session budget"
        );

        session.spentAmount += _amount;
        providerBalances[session.provider] += _amount;

        emit Settled(_sessionId, session.provider, _amount);
    }

    /// @notice Closes a session and refunds any unspent allocated funds back to the user.
    /// @param _sessionId The unique identifier for the session to close.

    function closeSession(byte32 _sessionId) external {
        Session storage session = sessions[_sessionId];
        require(session.isActive, "Session already closed");
        require(
            msg.sender == session.user || msg.sender == tempoGate,
            "Unauthorized"
        );

        session.isActive = false;

        uint256 unspent = session.allocatedAmount - session.spentAmount;

        if (unspent > 0) {
            userBalances[session.user] += unspent; // lock is released
        }

        emit SessionClosed(_sessionId, unspent);
    }

    /// @notice allows a provider to withdraw their accumulated earnings.
    function providerWithdraw() external nonReentrant {
        uint256 amount = providerBalances[msg.sender];
        require(amount > 0, "No funds avaliable to withdraw");

        // Update state before external call
        providerBalances[msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Provider transfer failed");

        emit ProviderWithdrawn(msg.sender, amount);
    }

    // -- Admin function
    /// @notice Allows the current gateway to transfer it's role to a new address.
    function updateTempoGate(address _newGate) external OnlyTempoGate {
        require(_newGate != address(0), "Invalid new gateway address");
        tempoGate = _newGate;
    }
}
