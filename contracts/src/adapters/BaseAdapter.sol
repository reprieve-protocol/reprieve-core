// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {IReprieveAdapter} from "../interfaces/IReprieveAdapter.sol";
import {ILendingLikeProtocol} from "../interfaces/ILendingLikeProtocol.sol";

interface IProtocolWithHF {
    function getUserPosition(address user) external view returns (ILendingLikeProtocol.Position memory);
    function getHealthFactor(address user) external view returns (uint256);
}

/**
 * @title BaseAdapter
 * @notice Base contract for Reprieve adapters with shared functionality
 * @dev Inherited by protocol-specific adapters (Aave, Compound, Morpho)
 */
abstract contract BaseAdapter is IReprieveAdapter, Ownable {
    using SafeERC20 for IERC20;

    /// @notice The underlying lending protocol
    address public immutable protocol;
    
    /// @notice Supported collateral asset
    address public immutable collateralAsset;
    
    /// @notice Supported debt asset  
    address public immutable debtAsset;
    
    /// @notice Name identifier for this adapter
    string public name;

    /// @notice Emergency pause switch
    bool public paused;

    /// @notice Minimum health factor to consider for rescue (WAD precision)
    uint256 public constant MIN_RESCUE_HF = 1.05e18; // 1.05 HF minimum

    error AdapterPaused();
    error UnsupportedAsset();
    error ZeroAmount();
    error ZeroAddress();
    error InsufficientCollateral();
    error WithdrawFailed();
    error RepayFailed();

    modifier whenNotPaused() {
        if (paused) revert AdapterPaused();
        _;
    }

    constructor(
        address _protocol,
        address _collateralAsset,
        address _debtAsset,
        string memory _name,
        address _owner
    ) Ownable(_owner) {
        if (_protocol == address(0) || _collateralAsset == address(0) || _debtAsset == address(0)) {
            revert ZeroAddress();
        }
        protocol = _protocol;
        collateralAsset = _collateralAsset;
        debtAsset = _debtAsset;
        name = _name;
    }

    // ============ View Functions ============

    function protocolName() external view override returns (string memory) {
        return name;
    }

    function protocolAddress() external view override returns (address) {
        return protocol;
    }

    function supportsPair(address _collateral, address _debt) external view override returns (bool) {
        return _collateral == collateralAsset && _debt == debtAsset;
    }

    // ============ Admin Functions ============

    function pause() external onlyOwner {
        paused = true;
    }

    function unpause() external onlyOwner {
        paused = false;
    }

    // ============ Internal Helpers ============

    /**
     * @notice Get protocol's position data and convert to adapter format
     */
    function _getPosition(address user) internal view returns (Position memory) {
        IProtocolWithHF proto = IProtocolWithHF(protocol);
        ILendingLikeProtocol.Position memory protoPos = proto.getUserPosition(user);
        uint256 hf = proto.getHealthFactor(user); // Price embedded in protocol
        
        return Position({
            protocol: protocol,
            collateralAsset: collateralAsset,
            debtAsset: debtAsset,
            collateralAmount: protoPos.collateral,
            debtAmount: protoPos.debt,
            healthFactor: hf,
            ltvBps: _calculateCurrentLTV(protoPos),
            maxLtvBps: protoPos.ltvBps,
            liquidationThresholdBps: protoPos.liquidationThresholdBps
        });
    }

    /**
     * @notice Calculate current LTV based on position data
     */
    function _calculateCurrentLTV(ILendingLikeProtocol.Position memory pos) internal pure returns (uint256) {
        if (pos.collateral == 0 || pos.debt == 0) return 0;
        // Simplified: assumes collateral and debt are roughly same value scale
        // In production, would use oracle prices
        return (pos.debt * 10000) / pos.collateral;
    }

    /**
     * @notice Validate asset is supported
     */
    function _validateAsset(address asset) internal view {
        if (asset != collateralAsset && asset != debtAsset) {
            revert UnsupportedAsset();
        }
    }
}
