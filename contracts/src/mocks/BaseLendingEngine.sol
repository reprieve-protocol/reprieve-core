// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {Pausable} from "@openzeppelin/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {DemoConstants} from "../libs/DemoConstants.sol";
import {LendingMath} from "../libs/LendingMath.sol";
import {ILendingLikeProtocol} from "../interfaces/ILendingLikeProtocol.sol";

/**
 * @title BaseLendingEngine
 * @notice Shared lending engine for Reprieve demo protocol mimics
 * @dev Handles collateral, debt, interest accrual, HF calculation, and liquidation
 * @dev Uses fixed 5% APR, 75% LTV, 80% liquidation threshold
 */
contract BaseLendingEngine is ILendingLikeProtocol, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ============ Structs ============
    
    struct UserPosition {
        uint256 collateral;           // Collateral amount (in collateral token decimals)
        uint256 debt;                 // Debt principal (in debt token decimals)
        uint256 debtAccrued;          // Total debt with interest (in debt token decimals)
        uint256 lastUpdateTime;       // Last interest accrual timestamp
    }
    
    struct RiskParams {
        uint256 maxLtvBps;                    // Maximum loan-to-value ratio
        uint256 liquidationThresholdBps;      // Liquidation threshold
        uint256 liquidationBonusBps;          // Liquidation bonus for liquidators
        uint256 borrowAprBps;                 // Fixed borrow APR
    }
    
    // ============ State Variables ============
    
    /// @notice Collateral token (e.g., WETH)
    IERC20 public immutable _collateralAsset;
    
    /// @notice Debt token (e.g., USDC)
    IERC20 public immutable _debtAsset;
    
    /// @notice Collateral token decimals
    uint8 public immutable collateralDecimals;
    
    /// @notice Debt token decimals
    uint8 public immutable debtDecimals;
    
    /// @notice User positions: user => position
    mapping(address => UserPosition) public positions;
    
    /// @notice Risk parameters
    RiskParams public riskParams;
    
    /// @notice Total collateral supplied
    uint256 public totalCollateral;
    
    /// @notice Total debt outstanding (with interest)
    uint256 public totalDebt;
    
    /// @notice Oracle address for price data
    address public oracle;
    
    /// @notice Authorized operators that can act on behalf of users (e.g., pools)
    mapping(address => bool) public authorizedOperators;
    
    // ============ Events ============
    
    event RiskParamsUpdated(uint256 maxLtvBps, uint256 liquidationThresholdBps, uint256 liquidationBonusBps, uint256 borrowAprBps);
    event OracleUpdated(address indexed newOracle);
    
    // ============ Errors ============
    
    error InvalidAmount();
    error InsufficientCollateral();
    error InsufficientDebt();
    error BorrowWouldExceedMaxLTV();
    error WithdrawWouldExceedMaxLTV();
    error PositionNotLiquidatable();
    error LiquidationBonusTransferFailed();
    error InvalidOracle();
    error InvalidRiskParams();
    error CannotLiquidateSelf();
    
    // ============ Constructor ============
    
    constructor(
        address collateralAsset_,
        address debtAsset_,
        address oracle_,
        address initialOwner
    ) Ownable(initialOwner) {
        if (collateralAsset_ == address(0) || debtAsset_ == address(0) || oracle_ == address(0)) {
            revert InvalidOracle();
        }
        
        _collateralAsset = IERC20(collateralAsset_);
        _debtAsset = IERC20(debtAsset_);
        oracle = oracle_;
        collateralDecimals = IERC20Metadata(collateralAsset_).decimals();
        debtDecimals = IERC20Metadata(debtAsset_).decimals();
        oracle = oracle_;
        
        // Set default risk parameters
        riskParams = RiskParams({
            maxLtvBps: DemoConstants.MAX_LTV_BPS,
            liquidationThresholdBps: DemoConstants.LIQUIDATION_THRESHOLD_BPS,
            liquidationBonusBps: DemoConstants.LIQUIDATION_BONUS_BPS,
            borrowAprBps: DemoConstants.BORROW_APR_BPS
        });
    }
    
    // ============ Modifiers ============
    
    /**
     * @notice Accrue interest before executing function
     */
    modifier accrueInterest(address user) {
        _accrueInterest(user);
        _;
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get user position data
     * @param user The address to query
     * @return Position struct with collateral, debt, LTV, and liquidation threshold
     */
    function getUserPosition(address user) external view override returns (Position memory) {
        UserPosition storage pos = positions[user];
        
        // Calculate current debt with interest
        uint256 currentDebt = _calculateCurrentDebt(user);
        
        return Position({
            collateral: pos.collateral,
            debt: currentDebt,
            ltvBps: riskParams.maxLtvBps,
            liquidationThresholdBps: riskParams.liquidationThresholdBps
        });
    }
    
    /**
     * @notice Calculate health factor for a user
     * @param user The address to query
     * @param price Current collateral price (WAD precision)
     * @return hfWad Health factor in WAD precision (1e18 = 1.0)
     */
    function getHealthFactor(address user, uint256 price) external view override returns (uint256 hfWad) {
        return _calculateHealthFactor(user, price);
    }
    
    /**
     * @notice Calculate current health factor using oracle price
     * @param user The address to query
     * @return hfWad Health factor in WAD precision
     */
    function getCurrentHealthFactor(address user) external view returns (uint256 hfWad) {
        (uint256 price, ) = IPriceOracle(oracle).getPrice(address(_collateralAsset));
        return _calculateHealthFactor(user, price);
    }
    
    /**
     * @notice Check if a position can be liquidated
     * @param user The address to check
     * @param price Current collateral price (WAD precision)
     * @return isLiquidatable True if HF < 1.0
     */
    function canLiquidate(address user, uint256 price) external view returns (bool isLiquidatable) {
        uint256 hf = _calculateHealthFactor(user, price);
        return hf < DemoConstants.WAD;
    }
    
    /**
     * @notice Get maximum borrowable amount for a user
     * @param user The address to query
     * @param price Current collateral price (WAD precision)
     * @return maxBorrow Maximum additional debt token amount
     */
    function maxBorrowAmount(address user, uint256 price) external view returns (uint256 maxBorrow) {
        UserPosition storage pos = positions[user];
        uint256 currentDebt = _calculateCurrentDebt(user);
        
        uint256 collateralValueUSD = LendingMath.collateralValueUSD(
            pos.collateral,
            price,
            collateralDecimals
        );
        
        uint256 maxBorrowUSD = LendingMath.calculateMaxBorrow(collateralValueUSD, riskParams.maxLtvBps);
        uint256 currentDebtUSD = (currentDebt * DemoConstants.WAD) / (10 ** debtDecimals); // Assume debt price = 1 USD
        
        if (maxBorrowUSD <= currentDebtUSD) {
            return 0;
        }
        
        uint256 availableUSD = maxBorrowUSD - currentDebtUSD;
        return (availableUSD * (10 ** debtDecimals)) / DemoConstants.WAD;
    }
    
    /**
     * @notice Get maximum withdrawable collateral for a user
     * @param user The address to query
     * @param price Current collateral price (WAD precision)
     * @return maxWithdraw Maximum withdrawable collateral amount
     */
    function maxWithdrawAmount(address user, uint256 price) external view returns (uint256 maxWithdraw) {
        UserPosition storage pos = positions[user];
        uint256 currentDebt = _calculateCurrentDebt(user);
        
        uint256 collateralValueUSD = LendingMath.collateralValueUSD(
            pos.collateral,
            price,
            collateralDecimals
        );
        
        uint256 currentDebtUSD = (currentDebt * DemoConstants.WAD) / (10 ** debtDecimals);
        uint256 maxWithdrawUSD = LendingMath.calculateMaxWithdraw(
            collateralValueUSD,
            currentDebtUSD,
            riskParams.maxLtvBps
        );
        
        return LendingMath.usdToTokenAmount(maxWithdrawUSD, price, collateralDecimals);
    }
    
    // ============ User Actions ============
    
    /**
     * @notice Supply collateral to the protocol
     * @param asset The collateral token address
     * @param amount The amount to supply
     * @param onBehalfOf The address to supply for
     */
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external override whenNotPaused nonReentrant accrueInterest(onBehalfOf) {
        if (asset != address(_collateralAsset)) revert InvalidAmount();
        if (amount == 0) revert InvalidAmount();
        if (onBehalfOf == address(0)) revert InvalidAmount();
        
        // Transfer collateral from user
        _collateralAsset.safeTransferFrom(msg.sender, address(this), amount);
        
        // Update position
        positions[onBehalfOf].collateral += amount;
        totalCollateral += amount;
        
        emit Supplied(onBehalfOf, asset, amount);
        emit PositionUpdated(
            onBehalfOf,
            positions[onBehalfOf].collateral,
            positions[onBehalfOf].debtAccrued,
            DemoConstants.WAD // HF is max if no debt
        );
    }
    
    /**
     * @notice Get collateral token address
     */
    function collateralAsset() external view override returns (address) {
        return address(_collateralAsset);
    }
    
    /**
     * @notice Get debt token address
     */
    function debtAsset() external view override returns (address) {
        return address(_debtAsset);
    }
    
    /**
     * @notice Withdraw collateral from the protocol
     * @param asset The collateral token address
     * @param amount The amount to withdraw
     * @param to The address to send withdrawn collateral to
     */
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external override whenNotPaused nonReentrant accrueInterest(msg.sender) {
        if (asset != address(_collateralAsset)) revert InvalidAmount();
        if (amount == 0) revert InvalidAmount();
        if (to == address(0)) revert InvalidAmount();
        
        UserPosition storage pos = positions[msg.sender];
        if (pos.collateral < amount) revert InsufficientCollateral();
        
        // Check withdrawal doesn't violate LTV
        uint256 newCollateral = pos.collateral - amount;
        uint256 debt = pos.debtAccrued;
        
        if (debt > 0) {
            (uint256 price, ) = IPriceOracle(oracle).getPrice(address(_collateralAsset));
            uint256 newCollateralValueUSD = LendingMath.collateralValueUSD(
                newCollateral,
                price,
                collateralDecimals
            );
            uint256 debtValueUSD = (debt * DemoConstants.WAD) / (10 ** debtDecimals);
            uint256 newLtvBps = LendingMath.calculateLTV(debtValueUSD, newCollateralValueUSD);
            
            if (newLtvBps > riskParams.maxLtvBps) {
                revert WithdrawWouldExceedMaxLTV();
            }
        }
        
        // Update state
        pos.collateral = newCollateral;
        totalCollateral -= amount;
        
        // Transfer collateral to recipient
        _collateralAsset.safeTransfer(to, amount);
        
        emit Withdrawn(msg.sender, asset, amount, to);
        _emitPositionUpdated(msg.sender);
    }
    
    /**
     * @notice Borrow debt asset from the protocol
     * @param asset The debt token address
     * @param amount The amount to borrow
     * @param onBehalfOf The address to borrow for
     */
    function borrow(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external override whenNotPaused nonReentrant accrueInterest(onBehalfOf) {
        if (asset != address(_debtAsset)) revert InvalidAmount();
        if (amount == 0) revert InvalidAmount();
        if (onBehalfOf == address(0)) revert InvalidAmount();
        
        UserPosition storage pos = positions[onBehalfOf];
        
        // Check if borrow would exceed max LTV
        (uint256 price, ) = IPriceOracle(oracle).getPrice(address(_collateralAsset));
        uint256 collateralValueUSD = LendingMath.collateralValueUSD(
            pos.collateral,
            price,
            collateralDecimals
        );
        
        uint256 currentDebt = pos.debtAccrued;
        uint256 newDebt = currentDebt + amount;
        uint256 newDebtValueUSD = (newDebt * DemoConstants.WAD) / (10 ** debtDecimals);
        uint256 maxDebtValueUSD = LendingMath.calculateMaxBorrow(collateralValueUSD, riskParams.maxLtvBps);
        
        if (newDebtValueUSD > maxDebtValueUSD) {
            revert BorrowWouldExceedMaxLTV();
        }
        
        // Update state
        pos.debt = newDebt;
        pos.debtAccrued = newDebt;
        totalDebt += amount;
        
        // Transfer debt tokens to borrower
        _debtAsset.safeTransfer(msg.sender, amount);
        
        emit Borrowed(onBehalfOf, asset, amount);
        _emitPositionUpdated(onBehalfOf);
    }
    
    /**
     * @notice Repay debt to the protocol
     * @param asset The debt token address
     * @param amount The amount to repay
     * @param onBehalfOf The address whose debt is being repaid
     */
    function repay(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external override whenNotPaused nonReentrant accrueInterest(onBehalfOf) {
        if (asset != address(_debtAsset)) revert InvalidAmount();
        if (amount == 0) revert InvalidAmount();
        if (onBehalfOf == address(0)) revert InvalidAmount();
        
        UserPosition storage pos = positions[onBehalfOf];
        uint256 currentDebt = pos.debtAccrued;
        
        if (currentDebt == 0) revert InsufficientDebt();
        
        // Cap repayment at current debt
        uint256 repayAmount = amount > currentDebt ? currentDebt : amount;
        
        // Transfer debt tokens from repayer
        _debtAsset.safeTransferFrom(msg.sender, address(this), repayAmount);
        
        // Update state
        pos.debtAccrued = currentDebt - repayAmount;
        pos.debt = pos.debtAccrued; // Reset principal to match accrued after full/partial repay
        totalDebt -= repayAmount;
        
        emit Repaid(msg.sender, asset, repayAmount, onBehalfOf);
        _emitPositionUpdated(onBehalfOf);
    }
    
    // ============ Liquidation ============
    
    /**
     * @notice Liquidate an unhealthy position
     * @param user The address to liquidate
     */
    function liquidate(address user) external override whenNotPaused nonReentrant accrueInterest(user) {
        if (user == msg.sender) revert CannotLiquidateSelf();
        
        UserPosition storage pos = positions[user];
        
        // Get current price and check if liquidatable
        (uint256 price, ) = IPriceOracle(oracle).getPrice(address(_collateralAsset));
        uint256 hf = _calculateHealthFactor(user, price);
        
        if (hf >= DemoConstants.WAD) {
            revert PositionNotLiquidatable();
        }
        
        uint256 debtToRepay = pos.debtAccrued;
        if (debtToRepay == 0) revert InsufficientDebt();
        
        // Calculate collateral to seize with liquidation bonus
        uint256 debtValueUSD = (debtToRepay * DemoConstants.WAD) / (10 ** debtDecimals);
        uint256 bonusValueUSD = LendingMath.liquidationBonus(debtValueUSD, riskParams.liquidationBonusBps);
        uint256 totalSeizeValueUSD = debtValueUSD + bonusValueUSD;
        
        uint256 collateralToSeize = LendingMath.usdToTokenAmount(
            totalSeizeValueUSD,
            price,
            collateralDecimals
        );
        
        // Cap at user's collateral
        if (collateralToSeize > pos.collateral) {
            collateralToSeize = pos.collateral;
        }
        
        // Transfer debt tokens from liquidator
        _debtAsset.safeTransferFrom(msg.sender, address(this), debtToRepay);
        
        // Update state
        pos.debtAccrued = 0;
        pos.debt = 0;
        pos.collateral -= collateralToSeize;
        totalDebt -= debtToRepay;
        totalCollateral -= collateralToSeize;
        
        // Transfer seized collateral to liquidator
        _collateralAsset.safeTransfer(msg.sender, collateralToSeize);
        
        emit Liquidated(user, msg.sender, debtToRepay, collateralToSeize);
        emit PositionUpdated(user, pos.collateral, 0, type(uint256).max);
    }
    
    // ============ Admin Functions ============
    
    /**
     * @notice Set risk parameters (owner only)
     * @param _maxLtvBps Maximum LTV in basis points
     * @param _liquidationThresholdBps Liquidation threshold in basis points
     * @param _liquidationBonusBps Liquidation bonus in basis points
     * @param _borrowAprBps Borrow APR in basis points
     */
    function setRiskParams(
        uint256 _maxLtvBps,
        uint256 _liquidationThresholdBps,
        uint256 _liquidationBonusBps,
        uint256 _borrowAprBps
    ) external onlyOwner {
        if (_maxLtvBps >= _liquidationThresholdBps) revert InvalidRiskParams();
        if (_liquidationThresholdBps > DemoConstants.BPS_BASE) revert InvalidRiskParams();
        if (_liquidationBonusBps > 1000) revert InvalidRiskParams(); // Max 10% bonus
        
        riskParams = RiskParams({
            maxLtvBps: _maxLtvBps,
            liquidationThresholdBps: _liquidationThresholdBps,
            liquidationBonusBps: _liquidationBonusBps,
            borrowAprBps: _borrowAprBps
        });
        
        emit RiskParamsUpdated(_maxLtvBps, _liquidationThresholdBps, _liquidationBonusBps, _borrowAprBps);
    }
    
    /**
     * @notice Set oracle address (owner only)
     * @param _oracle New oracle address
     */
    function setOracle(address _oracle) external onlyOwner {
        if (_oracle == address(0)) revert InvalidOracle();
        oracle = _oracle;
        emit OracleUpdated(_oracle);
    }
    
    /**
     * @notice Set authorized operator status (owner only)
     * @param operator Address to authorize
     * @param authorized True to authorize, false to revoke
     */
    function setAuthorizedOperator(address operator, bool authorized) external onlyOwner {
        authorizedOperators[operator] = authorized;
    }
    
    /**
     * @notice Withdraw collateral on behalf of a user (authorized operators only)
     * @param onBehalfOf User to withdraw for
     * @param asset Collateral asset
     * @param amount Amount to withdraw
     * @param to Recipient address
     */
    function withdrawOnBehalfOf(
        address onBehalfOf,
        address asset,
        uint256 amount,
        address to
    ) external whenNotPaused nonReentrant accrueInterest(onBehalfOf) {
        if (!authorizedOperators[msg.sender]) revert InvalidAmount();
        if (asset != address(_collateralAsset)) revert InvalidAmount();
        if (amount == 0) revert InvalidAmount();
        if (to == address(0)) revert InvalidAmount();
        
        UserPosition storage pos = positions[onBehalfOf];
        if (pos.collateral < amount) revert InsufficientCollateral();
        
        // Check withdrawal doesn't violate LTV
        uint256 newCollateral = pos.collateral - amount;
        uint256 debt = pos.debtAccrued;
        
        if (debt > 0) {
            (uint256 price, ) = IPriceOracle(oracle).getPrice(address(_collateralAsset));
            uint256 newCollateralValueUSD = LendingMath.collateralValueUSD(
                newCollateral,
                price,
                collateralDecimals
            );
            uint256 debtValueUSD = (debt * DemoConstants.WAD) / (10 ** debtDecimals);
            uint256 newLtvBps = LendingMath.calculateLTV(debtValueUSD, newCollateralValueUSD);
            
            if (newLtvBps > riskParams.maxLtvBps) {
                revert WithdrawWouldExceedMaxLTV();
            }
        }
        
        // Update state
        pos.collateral = newCollateral;
        totalCollateral -= amount;
        
        // Transfer collateral to recipient
        _collateralAsset.safeTransfer(to, amount);
        
        emit Withdrawn(onBehalfOf, asset, amount, to);
        _emitPositionUpdated(onBehalfOf);
    }
    
    /**
     * @notice Pause the contract (owner only)
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpause the contract (owner only)
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    // ============ Internal Functions ============
    
    /**
     * @notice Accrue interest for a user's position
     * @param user The user address
     */
    function _accrueInterest(address user) internal {
        UserPosition storage pos = positions[user];
        
        if (pos.debt == 0 || pos.lastUpdateTime == block.timestamp) {
            pos.lastUpdateTime = block.timestamp;
            return;
        }
        
        uint256 elapsedTime = block.timestamp - pos.lastUpdateTime;
        uint256 interest = LendingMath.calculateInterest(
            pos.debtAccrued,
            riskParams.borrowAprBps,
            elapsedTime
        );
        
        if (interest > 0) {
            pos.debtAccrued += interest;
            totalDebt += interest;
        }
        
        pos.lastUpdateTime = block.timestamp;
    }
    
    /**
     * @notice Calculate current debt including interest (without updating state)
     * @param user The user address
     * @return currentDebt Current debt amount
     */
    function _calculateCurrentDebt(address user) internal view returns (uint256 currentDebt) {
        UserPosition storage pos = positions[user];
        
        if (pos.debt == 0 || pos.lastUpdateTime == block.timestamp) {
            return pos.debtAccrued;
        }
        
        uint256 elapsedTime = block.timestamp - pos.lastUpdateTime;
        uint256 interest = LendingMath.calculateInterest(
            pos.debtAccrued,
            riskParams.borrowAprBps,
            elapsedTime
        );
        
        return pos.debtAccrued + interest;
    }
    
    /**
     * @notice Calculate health factor (internal)
     * @param user The user address
     * @param price Current collateral price
     * @return hfWad Health factor in WAD precision
     */
    function _calculateHealthFactor(
        address user,
        uint256 price
    ) internal view returns (uint256 hfWad) {
        UserPosition storage pos = positions[user];
        
        if (pos.debtAccrued == 0) {
            return type(uint256).max;
        }
        
        uint256 collateralValueUSD = LendingMath.collateralValueUSD(
            pos.collateral,
            price,
            collateralDecimals
        );
        
        uint256 debtValueUSD = (_calculateCurrentDebt(user) * DemoConstants.WAD) / (10 ** debtDecimals);
        
        return LendingMath.calculateHealthFactor(
            collateralValueUSD,
            debtValueUSD,
            riskParams.liquidationThresholdBps
        );
    }
    
    /**
     * @notice Emit PositionUpdated event with current HF
     * @param user The user address
     */
    function _emitPositionUpdated(address user) internal {
        UserPosition storage pos = positions[user];
        (uint256 price, ) = IPriceOracle(oracle).getPrice(address(_collateralAsset));
        uint256 hf = _calculateHealthFactor(user, price);
        
        emit PositionUpdated(user, pos.collateral, pos.debtAccrued, hf);
    }
}

/**
 * @title IPriceOracle
 * @notice Minimal interface for price oracle
 */
interface IPriceOracle {
    function getPrice(address asset) external view returns (uint256 price, uint256 timestamp);
}
