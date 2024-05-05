// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@crytic/properties/contracts/util/Hevm.sol";
import {TargetContractSetup} from "@ebtc/contracts/TestContracts/invariants/TargetContractSetup.sol";
import {CollateralTokenTester} from "@ebtc/contracts/TestContracts/CollateralTokenTester.sol";
import {Mock1Inch} from "@ebtc/contracts/TestContracts/Mock1Inch.sol";
import {EBTCTokenTester} from "@ebtc/contracts/TestContracts/EBTCTokenTester.sol";
import {ICdpManager} from "@ebtc/contracts/Interfaces/ICdpManager.sol";
import {IBorrowerOperations} from "@ebtc/contracts/Interfaces/IBorrowerOperations.sol";
import {IPositionManagers} from "@ebtc/contracts/Interfaces/IPositionManagers.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {WETH9} from "@ebtc/contracts/TestContracts/WETH9.sol";
import {IERC3156FlashLender} from "@ebtc/contracts/Interfaces/IERC3156FlashLender.sol";
import {IStETH} from "../../src/interface/IStETH.sol";
import {ZapRouterProperties} from "../../src/invariants/ZapRouterProperties.sol";
import {EbtcZapRouter} from "../../src/EbtcZapRouter.sol";
import {EbtcLeverageZapRouter} from "../../src/EbtcLeverageZapRouter.sol";
import {ZapRouterActor} from "../../src/invariants/ZapRouterActor.sol";
import {IEbtcZapRouter} from "../../src/interface/IEbtcZapRouter.sol";
import {IEbtcLeverageZapRouter} from "../../src/interface/IEbtcLeverageZapRouter.sol";
import {IEbtcZapRouterBase} from "../../src/interface/IEbtcZapRouterBase.sol";
import {WstETH} from "../../src/testContracts/WstETH.sol";
import {TargetFunctionsBase} from "./TargetFunctionsBase.sol";
import "forge-std/console2.sol";

abstract contract TargetFunctionsWithLeverage is TargetFunctionsBase {
    uint256 public constant MAXIMUM_DEBT = 1e27;
    uint256 public constant MAXIMUM_COLL = 2000000 ether;
    uint256 internal constant SLIPPAGE_PRECISION = 1e4;
    /// @notice Collateral buffer used to account for slippage and fees
    /// 9995 = 0.05%
    uint256 internal constant COLLATERAL_BUFFER = 9995;

    modifier setup() override {
        zapSender = msg.sender;
        zapActor = zapActors[msg.sender];
        zapActorKey = zapActorKeys[msg.sender];
        _;
    }

    function setUp() public virtual {
        super._setUp();
        mockDex = new Mock1Inch(address(eBTCToken), address(collateral));
        mockDex.setPrice(priceFeedMock.fetchPrice());
        testWeth = address(new WETH9());
        testWstEth = payable(new WstETH(address(collateral)));
        leverageZapRouter = new EbtcLeverageZapRouter(
            IEbtcLeverageZapRouter.DeploymentParams({
                borrowerOperations: address(borrowerOperations),
                activePool: address(activePool),
                cdpManager: address(cdpManager),
                ebtc: address(eBTCToken),
                stEth: address(collateral),
                weth: address(testWeth),
                wstEth: address(testWstEth),
                sortedCdps: address(sortedCdps),
                dex: address(mockDex),
                owner: defaultGovernance
            })
        );
    }

    function _seedActorAndPool() private {
        _seedActivePoolAndDex();
        _dealCollateral(zapActor, MAXIMUM_COLL, true);
        _dealWETH(zapActor, MAXIMUM_COLL, true);
        _dealWrappedCollateral(zapActor, MAXIMUM_COLL, true);
        _dealETH(zapActor, MAXIMUM_COLL);
        EBTCTokenTester(address(eBTCToken)).unprotectedMint(zapSender, MAXIMUM_DEBT * 2);
    }

    function _debtToCollateral(uint256 _debt) private returns (uint256) {
        uint256 price = priceFeedMock.fetchPrice();
        return (_debt * 1e18) / price;
    }

    function _collateralToDebt(uint256 _coll) private returns (uint256) {
        uint256 price = priceFeedMock.fetchPrice();
        return (_coll * price) / 1e18;
    }

    function _seedActivePoolAndDex() internal {
        // Give stETH to active pool
        _dealCollateral(zapActor, MAXIMUM_COLL * 2, false);

        bool success;
        bytes memory returnData;

        (success, returnData) = zapActor.proxy(
            address(collateral),
            abi.encodeWithSelector(CollateralTokenTester.transfer.selector, activePool, MAXIMUM_COLL * 2),
            false
        );
        t(success, "transfer cannot fail");

        // Give stETH to mock DEX
        _dealCollateral(zapActor, MAXIMUM_COLL * 2, false);

        (success, returnData) = zapActor.proxy(
            address(collateral),
            abi.encodeWithSelector(CollateralTokenTester.transfer.selector, mockDex, MAXIMUM_COLL * 2),
            false
        );
        t(success, "transfer cannot fail");

        EBTCTokenTester(address(eBTCToken)).unprotectedMint(address(mockDex), MAXIMUM_DEBT * 2);
    }

    function openCdpWithEth(uint256 _debt, uint256 _marginAmount) public setup {
        _openCdp(_debt, _marginAmount, MarginType.ETH);
    }

    function openCdpWithWrappedEth(uint256 _debt, uint256 _marginAmount) public setup {
        _openCdp(_debt, _marginAmount, MarginType.WETH);
    }

    function openCdpWithWstEth(uint256 _debt, uint256 _marginAmount) public setup {
        _openCdp(_debt, _marginAmount, MarginType.wstETH);
    }

    function openCdp(uint256 _debt, uint256 _marginAmount) public setup {
        _openCdp(_debt, _marginAmount, MarginType.stETH);
    }

    function _openCdp(uint256 _debt, uint256 _marginAmount, MarginType _marginType) internal {
        _seedActorAndPool();

        _debt = between(_debt, leverageZapRouter.MIN_CHANGE(), MAXIMUM_DEBT);
        _marginAmount = between(_marginAmount, leverageZapRouter.MIN_CHANGE(), MAXIMUM_COLL);

        uint256 flAmount = _debtToCollateral(_debt);
        uint256 totalDeposit = ((flAmount + _marginAmount) * COLLATERAL_BUFFER) / SLIPPAGE_PRECISION;

        bool success;
        bytes memory returnData;

        if (_marginType == MarginType.wstETH) {
            _marginAmount = WstETH(testWstEth).getWstETHByStETH(_marginAmount);
        }

        require(_isValidOperation(_debt, true, totalDeposit, 0));

        (success, returnData) = _openCdpInternal(_debt, flAmount, _marginAmount, totalDeposit, _marginType);

        if (!success) {
            if (_isValidTCR(_debt, true, totalDeposit, 0)) {
                uint256 cr = hintHelpers.computeCR(totalDeposit, _debt, priceFeedMock.fetchPrice());

                t(cr < borrowerOperations.MCR(), ZR_07);
            }
        }

        _checkApproval(address(leverageZapRouter));
    }

    function _isValidTCR(
        uint256 _debtChange, 
        bool _isDebtIncrease,
        uint256 _stEthBalanceIncrease,
        uint256 _stEthBalanceDecrease
    ) private view returns (bool) {
        uint price = priceFeedMock.getPrice();

        uint256 tcr = _getNewTCRFromCdpChange(
            _stEthBalanceIncrease > 0 ? _stEthBalanceIncrease : _stEthBalanceDecrease,
            _stEthBalanceIncrease > 0,
            _debtChange,
            _isDebtIncrease,
            price
        );

        if (tcr < borrowerOperations.CCR()) {
            return false;
        }
    }

    function _isValidOperation(
        uint256 _debtChange, 
        bool _isDebtIncrease,
        uint256 _stEthBalanceIncrease,
        uint256 _stEthBalanceDecrease
    ) private view returns (bool) {
        if (_debtChange == 0 && _stEthBalanceIncrease == 0 && _stEthBalanceDecrease == 0) {
            return false;
        }
        if (_debtChange > 0 && _debtChange < leverageZapRouter.MIN_CHANGE()) {
            return false;         
        }
        if (_stEthBalanceIncrease > 0 && _stEthBalanceDecrease > 0) {
            return false;
        }
        if (_stEthBalanceIncrease > 0 && _stEthBalanceIncrease < leverageZapRouter.MIN_CHANGE()) {
            return false;
        }
        if (_stEthBalanceDecrease > 0 && _stEthBalanceDecrease < leverageZapRouter.MIN_CHANGE()) {
            return false;
        }

        return true;
    }

    function _openCdpInternal(
        uint256 _debt,
        uint256 _flAmount,
        uint256 _marginAmount,
        uint256 _totalAmount,
        MarginType _marginType
    ) internal returns (bool success, bytes memory returnData) {
        uint256 msgValue;
        if (_marginType == MarginType.ETH) {
            msgValue = _marginAmount;
        }
        return
            zapActor.proxy(
                address(leverageZapRouter),
                _encodeOpenParams(_debt, _flAmount, _marginAmount, _totalAmount, _marginType),
                msgValue,
                true
            );
    }

    function _getOpenSelectorByMarginType(MarginType _marginType) private view returns (bytes4) {
        if (_marginType == MarginType.stETH) {
            return IEbtcLeverageZapRouter.openCdp.selector;
        } else if (_marginType == MarginType.wstETH) {
            return IEbtcLeverageZapRouter.openCdpWithWstEth.selector;
        } else if (_marginType == MarginType.ETH) {
            return IEbtcLeverageZapRouter.openCdpWithEth.selector;
        } else if (_marginType == MarginType.WETH) {
            return IEbtcLeverageZapRouter.openCdpWithWrappedEth.selector;
        } else {
            revert();
        }
    }

    function _encodeOpenParams(
        uint256 _debt,
        uint256 _flAmount,
        uint256 _marginAmount,
        uint256 _totalAmount,
        MarginType _marginType
    ) internal returns (bytes memory) {
        IEbtcZapRouterBase.PositionManagerPermit memory pmPermit = _generateOneTimePermit(
            address(zapSender),
            address(leverageZapRouter),
            zapActorKey
        );

        return
            abi.encodeWithSelector(
                _getOpenSelectorByMarginType(_marginType),
                _debt,
                bytes32(0),
                bytes32(0),
                _flAmount,
                _marginAmount,
                _totalAmount,
                abi.encode(pmPermit),
                _getExactInDebtToCollateralTradeData(_debt)
            );
    }

    function _getExactInDebtToCollateralTradeData(
        uint256 _amount
    ) private view returns (IEbtcLeverageZapRouter.TradeData memory) {
        return IEbtcLeverageZapRouter.TradeData({
            performSwapChecks: false,
            expectedMinOut: 0,
            exchangeData: abi.encodeWithSelector(
                mockDex.swap.selector,
                address(eBTCToken),
                address(collateral),
                _amount // Debt amount
            ),
            approvalAmount: _amount
        });
    }

    function _getExactOutCollateralDebtToTradeData(
        uint256 _debtAmount,
        uint256 _collAmount
    ) private view returns (IEbtcLeverageZapRouter.TradeData memory) {
        uint256 flashFee = IERC3156FlashLender(address(borrowerOperations)).flashFee(
            address(eBTCToken),
            _debtAmount
        );

        return IEbtcLeverageZapRouter.TradeData({
            performSwapChecks: false,
            expectedMinOut: 0,
            exchangeData: abi.encodeWithSelector(
                mockDex.swapExactOut.selector,
                address(collateral),
                address(eBTCToken),
                _debtAmount + flashFee // Debt amount
            ),
            approvalAmount: _collAmount
        });
    }

    function _getNewTCRFromCdpChange(
        uint256 _stEthBalanceChange,
        bool _isCollIncrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        uint256 _price
    ) internal view returns (uint256) {
        uint256 _systemCollShares = activePool.getSystemCollShares();
        uint256 systemStEthBalance = collateral.getPooledEthByShares(_systemCollShares);
        uint256 systemDebt = activePool.getSystemDebt();

        systemStEthBalance = _isCollIncrease
            ? systemStEthBalance + _stEthBalanceChange
            : systemStEthBalance - _stEthBalanceChange;
        systemDebt = _isDebtIncrease ? systemDebt + _debtChange : systemDebt - _debtChange;

        uint256 newTCR = hintHelpers.computeCR(systemStEthBalance, systemDebt, _price);
        return newTCR;
    }

    function _getNewICRFromCdpChange(
        uint256 _collShares,
        uint256 _debt,
        uint256 _collSharesChange,
        bool _isCollIncrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        uint256 _price
    ) internal view returns (uint256) {
        (uint256 newCollShares, uint256 newDebt) = _getNewCdpAmounts(
            _collShares,
            _debt,
            _collSharesChange,
            _isCollIncrease,
            _debtChange,
            _isDebtIncrease
        );

        uint256 newICR = hintHelpers.computeCR(
            collateral.getPooledEthByShares(newCollShares),
            newDebt,
            _price
        );
        return newICR;
    }

    function _getNewCdpAmounts(
        uint256 _collShares,
        uint256 _debt,
        uint256 _collSharesChange,
        bool _isCollIncrease,
        uint256 _debtChange,
        bool _isDebtIncrease
    ) internal pure returns (uint256, uint256) {
        uint256 newCollShares = _collShares;
        uint256 newDebt = _debt;

        newCollShares = _isCollIncrease
            ? _collShares + _collSharesChange
            : _collShares - _collSharesChange;
        newDebt = _isDebtIncrease ? _debt + _debtChange : _debt - _debtChange;

        return (newCollShares, newDebt);
    }

    function closeCdp(uint _i) public setup {
        bool success;
        bytes memory returnData;

        require(cdpManager.getActiveCdpsCount() > 1, "Cannot close last CDP");

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(zapSender));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = between(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(zapSender), _i);
        t(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        _seedActorAndPool();

        IEbtcZapRouterBase.PositionManagerPermit memory pmPermit = _generateOneTimePermit(
            address(zapSender),
            address(leverageZapRouter),
            zapActorKey
        );

        (uint256 debt, uint256 collShares) = cdpManager.getSyncedDebtAndCollShares(_cdpId);

        (success, returnData) = zapActor.proxy(
            address(leverageZapRouter),
            abi.encodeWithSelector(
                IEbtcLeverageZapRouter.closeCdp.selector,
                _cdpId,
                abi.encode(pmPermit),
                _getExactOutCollateralDebtToTradeData(
                    debt, 
                    collateral.getPooledEthByShares(collShares) * COLLATERAL_BUFFER / SLIPPAGE_PRECISION
                )
            ),
            true
        );

        if (!success) {
            if (_isValidTCR(debt, false, 0, collateral.getPooledEthByShares(collShares))) {
                t(success, "Call shouldn't fail");
            }
        }

        _checkApproval(address(leverageZapRouter));
    }

    function adjustDebt(uint _i, uint256 _debtChange, bool _isDebtIncrease) public setup {
        require(cdpManager.getActiveCdpsCount() > 1, "Cannot close last CDP");

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(zapSender));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = between(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(zapSender), _i);
        t(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        _seedActorAndPool();

        uint256 maxDebtAdjust = _collateralToDebt(MAXIMUM_COLL / 10);

        (uint256 debt, uint256 coll) = cdpManager.getSyncedDebtAndCollShares(_cdpId);
        
        if (_isDebtIncrease) {
            _debtChange = between(_debtChange, leverageZapRouter.MIN_CHANGE(), maxDebtAdjust);
        } else {
            _debtChange = between(_debtChange, leverageZapRouter.MIN_CHANGE(), debt);
        }

        _adjustDebt(_cdpId, debt, coll, _debtChange, _isDebtIncrease);
    }

    function _adjustDebt(
        bytes32 _cdpId,
        uint256 debt,
        uint256 coll,
        uint256 _debtChange,
        bool _isDebtIncrease
    ) private {
        require(_isValidOperation(_debtChange, _isDebtIncrease, 0, 0));

        bool success;
        uint256 collValue;
        bool collIncrease;
        if (_isDebtIncrease) {
            (success, collValue) = _adjustDebtIncrease(_cdpId, _debtChange);
            collIncrease = true;
        } else {
            (success, collValue) = _adjustDebtDecrease(_cdpId, _debtChange);
            collIncrease = false;
        }

        if (!success) {
            if (!_isDebtIncrease && debt - _debtChange < leverageZapRouter.MIN_CHANGE()) {
                // below min debt, do nothing
            } else {
                uint256 icr = _getNewICRFromCdpChange(
                    coll,
                    debt,
                    collateral.getSharesByPooledEth(collValue),
                    collIncrease,
                    _debtChange,
                    _isDebtIncrease,
                    priceFeedMock.fetchPrice()
                );
                    
                t(icr < borrowerOperations.MCR(), ZR_07);                
            }
        }

        _checkApproval(address(leverageZapRouter));
    }

    function _adjustDebtIncrease(
        bytes32 _cdpId,
        uint256 _debtChange
    ) internal returns (bool success, uint256 collValue) {
        IEbtcZapRouterBase.PositionManagerPermit memory pmPermit = _generateOneTimePermit(
            address(zapSender),
            address(leverageZapRouter),
            zapActorKey
        );

        collValue = (_debtToCollateral(_debtChange) * 9995) / 10000;

        (success, ) = zapActor.proxy(
            address(leverageZapRouter),
            abi.encodeWithSelector(
                IEbtcLeverageZapRouter.adjustCdp.selector,
                _cdpId,
                IEbtcLeverageZapRouter.AdjustCdpParams({
                    flashLoanAmount: _debtToCollateral(_debtChange),
                    debtChange: _debtChange,
                    isDebtIncrease: true,
                    upperHint: bytes32(0),
                    lowerHint: bytes32(0),
                    stEthBalanceChange: collValue,
                    isStEthBalanceIncrease: true,
                    stEthMarginBalance: 0,
                    isStEthMarginIncrease: false,
                    useWstETHForDecrease: false
                }),
                abi.encode(pmPermit),
                _getExactInDebtToCollateralTradeData(_debtChange)
            ),
            true
        );
    }

    function _adjustDebtDecrease(
        bytes32 _cdpId,
        uint256 _debtChange
    ) internal returns (bool success, uint256 collValue) {
        IEbtcZapRouterBase.PositionManagerPermit memory pmPermit = _generateOneTimePermit(
            address(zapSender),
            address(leverageZapRouter),
            zapActorKey
        );

        collValue = _debtToCollateral(_debtChange) * 10005 / 10000;

        (success, ) = zapActor.proxy(
            address(leverageZapRouter),
            abi.encodeWithSelector(
                IEbtcLeverageZapRouter.adjustCdp.selector,
                _cdpId,
                IEbtcLeverageZapRouter.AdjustCdpParams({
                    flashLoanAmount: _debtChange,
                    debtChange: _debtChange,
                    isDebtIncrease: false,
                    upperHint: bytes32(0),
                    lowerHint: bytes32(0),
                    stEthBalanceChange: collValue,
                    isStEthBalanceIncrease: false,
                    stEthMarginBalance: 0,
                    isStEthMarginIncrease: false,
                    useWstETHForDecrease: false
                }),
                abi.encode(pmPermit),
                _getExactOutCollateralDebtToTradeData(_debtChange, _debtToCollateral(_debtChange) * 10005 / 10000)
            ),
            true
        );
    }
}
