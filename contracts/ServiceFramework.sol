// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Minimal Ownable implementation for protocol fee management.
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), _owner);
    }
    
    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }
    
    function owner() public view returns (address) {
        return _owner;
    }
    
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

/// @notice Minimal ERC20 interface.
interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

/// @notice Minimal ERC721 interface for token-gated access.
interface IERC721 {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title ServiceFramework
/// @notice A general-purpose on-chain framework for registering and executing services on FEVM.
contract ServiceFramework is Ownable {
    
    // Enum to define access control types.
    enum AccessType { Public, Whitelisted, TokenGated }
    
    // Service structure definition.
    struct Service {
        uint256 serviceId;         // Unique service identifier.
        address provider;          // Service provider (registrant).
        address target;            // Address of the contract containing the callable function.
        bytes4 functionSelector;   // ABI function selector (first 4 bytes).
        uint256 fee;               // Service fee (in wei or smallest token unit).
        address paymentToken;      // Payment token address (zero means native FIL).
        AccessType accessType;     // Access control type.
        address tokenGate;         // Required token contract for token-gated access.
        uint256 gasLimit;          // Gas limit for execution.
        string metadata;           // Optional metadata (description, docs URL, versioning).
        bool active;               // Service status.
    }
    
    // Mapping of service ID to Service record.
    mapping(uint256 => Service) public services;
    uint256 public nextServiceId;
    
    // Mapping for whitelisted addresses for a service.
    mapping(uint256 => mapping(address => bool)) public serviceWhitelist;
    
    // Protocol fee settings.
    uint256 public protocolFeePercentage; // e.g., 5 for 5%
    address public protocolFeeRecipient;
    
    // --- Events ---
    event ServiceRegistered(uint256 indexed serviceId, address indexed provider);
    event ServiceUpdated(uint256 indexed serviceId);
    event ServiceDeregistered(uint256 indexed serviceId);
    event ServiceExecuted(uint256 indexed serviceId, address indexed user, bool success);
    
    // --- Constructor ---
    constructor(uint256 _protocolFeePercentage, address _protocolFeeRecipient) {
        protocolFeePercentage = _protocolFeePercentage;
        protocolFeeRecipient = _protocolFeeRecipient;
        nextServiceId = 1;
    }
    
    // --- Admin Functions ---
    /// @notice Update the protocol fee percentage.
    function setProtocolFeePercentage(uint256 _protocolFeePercentage) external onlyOwner {
        protocolFeePercentage = _protocolFeePercentage;
    }
    
    /// @notice Update the protocol fee recipient.
    function setProtocolFeeRecipient(address _protocolFeeRecipient) external onlyOwner {
        require(_protocolFeeRecipient != address(0), "Invalid address");
        protocolFeeRecipient = _protocolFeeRecipient;
    }
    
    // --- Service Registry Functions ---
    /// @notice Register a new service.
    /// @param target Address of the target contract.
    /// @param functionSelector The function selector for the callable function.
    /// @param fee Payment fee required to execute the service.
    /// @param paymentToken Address of the token accepted for payment (zero for native FIL).
    /// @param accessType Access control mode (Public, Whitelisted, TokenGated).
    /// @param tokenGate For token-gated services, the required token contract address.
    /// @param gasLimit Gas limit to use when executing the service call.
    /// @param metadata Optional metadata (description, docs URL, etc.).
    /// @return serviceId The unique ID of the registered service.
    function registerService(
        address target,
        bytes4 functionSelector,
        uint256 fee,
        address paymentToken,
        AccessType accessType,
        address tokenGate,
        uint256 gasLimit,
        string calldata metadata
    ) external returns (uint256 serviceId) {
        serviceId = nextServiceId++;
        services[serviceId] = Service({
            serviceId: serviceId,
            provider: msg.sender,
            target: target,
            functionSelector: functionSelector,
            fee: fee,
            paymentToken: paymentToken,
            accessType: accessType,
            tokenGate: tokenGate,
            gasLimit: gasLimit,
            metadata: metadata,
            active: true
        });
        emit ServiceRegistered(serviceId, msg.sender);
    }
    
    /// @notice Update an existing service. Only the provider can update.
    function updateService(
       uint256 serviceId,
       address target,
       bytes4 functionSelector,
       uint256 fee,
       address paymentToken,
       AccessType accessType,
       address tokenGate,
       uint256 gasLimit,
       string calldata metadata,
       bool active
    ) external {
        Service storage s = services[serviceId];
        require(s.provider == msg.sender, "Only provider can update");
        s.target = target;
        s.functionSelector = functionSelector;
        s.fee = fee;
        s.paymentToken = paymentToken;
        s.accessType = accessType;
        s.tokenGate = tokenGate;
        s.gasLimit = gasLimit;
        s.metadata = metadata;
        s.active = active;
        emit ServiceUpdated(serviceId);
    }
    
    /// @notice Deregister (deactivate) a service. Only the provider can call.
    function deregisterService(uint256 serviceId) external {
       Service storage s = services[serviceId];
       require(s.provider == msg.sender, "Only provider can deregister");
       s.active = false;
       emit ServiceDeregistered(serviceId);
    }
    
    /// @notice Add an address to a service’s whitelist.
    function addToWhitelist(uint256 serviceId, address user) external {
       Service storage s = services[serviceId];
       require(s.provider == msg.sender, "Only provider can add whitelist");
       serviceWhitelist[serviceId][user] = true;
    }
    
    /// @notice Remove an address from a service’s whitelist.
    function removeFromWhitelist(uint256 serviceId, address user) external {
       Service storage s = services[serviceId];
       require(s.provider == msg.sender, "Only provider can remove whitelist");
       serviceWhitelist[serviceId][user] = false;
    }
    
    // --- Access & Execution ---
    /// @notice Execute a registered service.
    /// @param serviceId The ID of the service to call.
    /// @param data Encoded parameters (excluding the selector) for the target function.
    function executeService(uint256 serviceId, bytes calldata data) external payable {
       Service memory s = services[serviceId];
       require(s.active, "Service is not active");
       
       // --- Access Control ---
       if (s.accessType == AccessType.Whitelisted) {
          require(serviceWhitelist[serviceId][msg.sender], "Not whitelisted");
       } else if (s.accessType == AccessType.TokenGated) {
          // For token gated, check if user owns at least one token.
          IERC721 token = IERC721(s.tokenGate);
          require(token.balanceOf(msg.sender) > 0, "Token not held for access");
       }
       
       // --- Payment Handling ---
       if (s.paymentToken == address(0)) {
           // Payment in native FIL.
           require(msg.value >= s.fee, "Insufficient payment");
           uint256 protocolFee = (s.fee * protocolFeePercentage) / 100;
           uint256 providerAmount = s.fee - protocolFee;
           // Transfer protocol fee.
           payable(protocolFeeRecipient).transfer(protocolFee);
           // Transfer remaining amount to service provider.
           payable(s.provider).transfer(providerAmount);
           // Refund excess if overpaid.
           if (msg.value > s.fee) {
               payable(msg.sender).transfer(msg.value - s.fee);
           }
       } else {
           // Payment in ERC20 token.
           IERC20 token = IERC20(s.paymentToken);
           require(token.transferFrom(msg.sender, address(this), s.fee), "Token payment failed");
           uint256 protocolFee = (s.fee * protocolFeePercentage) / 100;
           uint256 providerAmount = s.fee - protocolFee;
           require(token.transfer(protocolFeeRecipient, protocolFee), "Protocol fee transfer failed");
           require(token.transfer(s.provider, providerAmount), "Provider fee transfer failed");
       }
       
       // --- Service Execution ---
       // Concatenate the function selector with the provided parameters.
       bytes memory callData = abi.encodePacked(s.functionSelector, data);
       (bool success, ) = s.target.call{gas: s.gasLimit}(callData);
       emit ServiceExecuted(serviceId, msg.sender, success);
       require(success, "Service execution failed");
    }
}

