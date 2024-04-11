pragma solidity 0.8.17;

import {Pretty, Strings} from "@ebtc/contracts/TestContracts/Pretty.sol";
import {ZapRouterBaseStorageVariables} from "./ZapRouterBaseStorageVariables.sol";

abstract contract ZapRouterStateSnapshots is ZapRouterBaseStorageVariables {
    using Strings for string;
    using Pretty for uint256;
    using Pretty for int256;
    using Pretty for bool;

    struct EbtcState {
        uint256 valueInSystem;
        uint256 nicr;
        uint256 icr;
        uint256 newIcr;
        uint256 feeSplit;
        uint256 feeRecipientTotalColl;
        uint256 feeRecipientCollShares;
        uint256 actorColl;
        uint256 actorEbtc;
        uint256 actorCdpCount;
        uint256 cdpColl;
        uint256 cdpDebt;
        uint256 liquidatorRewardShares;
        uint256 sortedCdpsSize;
        uint256 cdpStatus;
        uint256 tcr;
        uint256 newTcr;
        uint256 ebtcTotalSupply;
        uint256 ethPerShare;
        uint256 activePoolColl;
        uint256 activePoolDebt;
        uint256 collSurplusPool;
        uint256 price;
        bool isRecoveryMode;
        uint256 lastGracePeriodStartTimestamp;
        bool lastGracePeriodStartTimestampIsSet;
        bool hasGracePeriodPassed;
        uint256 systemDebtRedistributionIndex;
    }

    struct ZapRouterState {
        uint256 EthBalance;
        uint256 WethBalance;
        uint256 stEthBalance;
        uint256 wstEthBalance;
        uint256 eBTCBalance;
        uint256 collShares;
    }

    EbtcState ebtcBefore;
    ZapRouterState zapBefore;
    EbtcState ebtcAfter;
    ZapRouterState zapAfter;

    function _before(bytes32 _cdpId, address _user) internal {
        ebtcBefore.price = priceFeedMock.fetchPrice();

        (uint256 debt, ) = cdpManager.getSyncedDebtAndCollShares(_cdpId);

        ebtcBefore.nicr = _cdpId != bytes32(0)
            ? crLens.quoteRealNICR(_cdpId)
            : 0;
        ebtcBefore.icr = _cdpId != bytes32(0)
            ? cdpManager.getCachedICR(_cdpId, ebtcBefore.price)
            : 0;
        ebtcBefore.cdpColl = _cdpId != bytes32(0)
            ? cdpManager.getCdpCollShares(_cdpId)
            : 0;
        ebtcBefore.cdpDebt = _cdpId != bytes32(0) ? debt : 0;
        ebtcBefore.liquidatorRewardShares = _cdpId != bytes32(0)
            ? cdpManager.getCdpLiquidatorRewardShares(_cdpId)
            : 0;
        ebtcBefore.cdpStatus = _cdpId != bytes32(0)
            ? cdpManager.getCdpStatus(_cdpId)
            : 0;

        ebtcBefore.isRecoveryMode = crLens.quoteCheckRecoveryMode() == 1; /// @audit crLens
        (ebtcBefore.feeSplit, , ) = collateral.getPooledEthByShares(
            cdpManager.DECIMAL_PRECISION()
        ) > cdpManager.stEthIndex()
            ? cdpManager.calcFeeUponStakingReward(
                collateral.getPooledEthByShares(cdpManager.DECIMAL_PRECISION()),
                cdpManager.stEthIndex()
            )
            : (0, 0, 0);
        ebtcBefore.feeRecipientTotalColl = collateral.balanceOf(
            activePool.feeRecipientAddress()
        );
        ebtcBefore.feeRecipientCollShares = activePool
            .getFeeRecipientClaimableCollShares();
        ebtcBefore.actorColl = collateral.balanceOf(address(actor));
        ebtcBefore.actorEbtc = eBTCToken.balanceOf(address(actor));
        ebtcBefore.actorCdpCount = sortedCdps.cdpCountOf(address(actor));
        ebtcBefore.sortedCdpsSize = sortedCdps.getSize();
        ebtcBefore.tcr = cdpManager.getCachedTCR(ebtcBefore.price);
        ebtcBefore.ebtcTotalSupply = eBTCToken.totalSupply();
        ebtcBefore.ethPerShare = collateral.getEthPerShare();
        ebtcBefore.activePoolDebt = activePool.getSystemDebt();
        ebtcBefore.activePoolColl = activePool.getSystemCollShares();
        ebtcBefore.collSurplusPool = collSurplusPool
            .getTotalSurplusCollShares();
        ebtcBefore.lastGracePeriodStartTimestamp = cdpManager
            .lastGracePeriodStartTimestamp();
        ebtcBefore.lastGracePeriodStartTimestampIsSet =
            cdpManager.lastGracePeriodStartTimestamp() !=
            cdpManager.UNSET_TIMESTAMP();
        ebtcBefore.hasGracePeriodPassed =
            cdpManager.lastGracePeriodStartTimestamp() !=
            cdpManager.UNSET_TIMESTAMP() &&
            block.timestamp >
            cdpManager.lastGracePeriodStartTimestamp() +
                cdpManager.recoveryModeGracePeriodDuration();
        ebtcBefore.systemDebtRedistributionIndex = cdpManager
            .systemDebtRedistributionIndex();
        ebtcBefore.newTcr = crLens.quoteRealTCR();
        ebtcBefore.newIcr = crLens.quoteRealICR(_cdpId);

        ebtcBefore.valueInSystem ==
            (collateral.getPooledEthByShares(
                ebtcBefore.activePoolColl +
                    ebtcBefore.collSurplusPool +
                    ebtcBefore.feeRecipientTotalColl
            ) * ebtcBefore.price) /
                1e18 -
                ebtcBefore.activePoolDebt;
    }

    function _after(bytes32 _cdpId, address _user) internal {
        ebtcAfter.price = priceFeedMock.fetchPrice();

        ebtcAfter.nicr = _cdpId != bytes32(0)
            ? crLens.quoteRealNICR(_cdpId)
            : 0;
        ebtcAfter.icr = _cdpId != bytes32(0)
            ? cdpManager.getCachedICR(_cdpId, ebtcAfter.price)
            : 0;
        ebtcAfter.cdpColl = _cdpId != bytes32(0)
            ? cdpManager.getCdpCollShares(_cdpId)
            : 0;
        ebtcAfter.cdpDebt = _cdpId != bytes32(0)
            ? cdpManager.getCdpDebt(_cdpId)
            : 0;
        ebtcAfter.liquidatorRewardShares = _cdpId != bytes32(0)
            ? cdpManager.getCdpLiquidatorRewardShares(_cdpId)
            : 0;
        ebtcAfter.cdpStatus = _cdpId != bytes32(0)
            ? cdpManager.getCdpStatus(_cdpId)
            : 0;

        ebtcAfter.isRecoveryMode = cdpManager.checkRecoveryMode(
            ebtcAfter.price
        ); /// @audit This is fine as is because after the system is synched
        (ebtcAfter.feeSplit, , ) = collateral.getPooledEthByShares(
            cdpManager.DECIMAL_PRECISION()
        ) > cdpManager.stEthIndex()
            ? cdpManager.calcFeeUponStakingReward(
                collateral.getPooledEthByShares(cdpManager.DECIMAL_PRECISION()),
                cdpManager.stEthIndex()
            )
            : (0, 0, 0);

        ebtcAfter.feeRecipientTotalColl = collateral.balanceOf(
            activePool.feeRecipientAddress()
        );
        ebtcAfter.feeRecipientCollShares = activePool
            .getFeeRecipientClaimableCollShares();
        ebtcAfter.actorColl = collateral.balanceOf(address(actor));
        ebtcAfter.actorEbtc = eBTCToken.balanceOf(address(actor));
        ebtcAfter.actorCdpCount = sortedCdps.cdpCountOf(address(actor));
        ebtcAfter.sortedCdpsSize = sortedCdps.getSize();
        ebtcAfter.tcr = cdpManager.getCachedTCR(ebtcAfter.price);
        ebtcAfter.ebtcTotalSupply = eBTCToken.totalSupply();
        ebtcAfter.ethPerShare = collateral.getEthPerShare();
        ebtcAfter.activePoolDebt = activePool.getSystemDebt();
        ebtcAfter.activePoolColl = activePool.getSystemCollShares();
        ebtcAfter.collSurplusPool = collSurplusPool.getTotalSurplusCollShares();
        ebtcAfter.lastGracePeriodStartTimestamp = cdpManager
            .lastGracePeriodStartTimestamp();
        ebtcAfter.lastGracePeriodStartTimestampIsSet =
            cdpManager.lastGracePeriodStartTimestamp() !=
            cdpManager.UNSET_TIMESTAMP();
        ebtcAfter.hasGracePeriodPassed =
            cdpManager.lastGracePeriodStartTimestamp() !=
            cdpManager.UNSET_TIMESTAMP() &&
            block.timestamp >
            cdpManager.lastGracePeriodStartTimestamp() +
                cdpManager.recoveryModeGracePeriodDuration();
        ebtcAfter.systemDebtRedistributionIndex = cdpManager
            .systemDebtRedistributionIndex();

        ebtcAfter.newTcr = crLens.quoteRealTCR();
        ebtcAfter.newIcr = crLens.quoteRealICR(_cdpId);

        // Value in system after
        ebtcAfter.valueInSystem =
            (collateral.getPooledEthByShares(
                ebtcAfter.activePoolColl +
                    ebtcAfter.collSurplusPool +
                    ebtcAfter.feeRecipientTotalColl
            ) * ebtcAfter.price) /
            1e18 -
            ebtcAfter.activePoolDebt;
    }

    function _diff() internal view returns (string memory log) {
        log = string("\n\t\t\t\tBefore\t\t\tAfter\n");
        if (ebtcBefore.activePoolColl != ebtcAfter.activePoolColl) {
            log = log
                .concat("activePoolColl\t\t\t")
                .concat(ebtcBefore.activePoolColl.pretty())
                .concat("\t")
                .concat(ebtcAfter.activePoolColl.pretty())
                .concat("\n");
        }
        if (ebtcBefore.collSurplusPool != ebtcAfter.collSurplusPool) {
            log = log
                .concat("collSurplusPool\t\t\t")
                .concat(ebtcBefore.collSurplusPool.pretty())
                .concat("\t")
                .concat(ebtcAfter.collSurplusPool.pretty())
                .concat("\n");
        }
        if (ebtcBefore.nicr != ebtcAfter.nicr) {
            log = log
                .concat("nicr\t\t\t\t")
                .concat(ebtcBefore.nicr.pretty())
                .concat("\t")
                .concat(ebtcAfter.nicr.pretty())
                .concat("\n");
        }
        if (ebtcBefore.icr != ebtcAfter.icr) {
            log = log
                .concat("icr\t\t\t\t")
                .concat(ebtcBefore.icr.pretty())
                .concat("\t")
                .concat(ebtcAfter.icr.pretty())
                .concat("\n");
        }
        if (ebtcBefore.newIcr != ebtcAfter.newIcr) {
            log = log
                .concat("newIcr\t\t\t\t")
                .concat(ebtcBefore.newIcr.pretty())
                .concat("\t")
                .concat(ebtcAfter.newIcr.pretty())
                .concat("\n");
        }
        if (ebtcBefore.feeSplit != ebtcAfter.feeSplit) {
            log = log
                .concat("feeSplit\t\t\t\t")
                .concat(ebtcBefore.feeSplit.pretty())
                .concat("\t")
                .concat(ebtcAfter.feeSplit.pretty())
                .concat("\n");
        }
        if (
            ebtcBefore.feeRecipientTotalColl != ebtcAfter.feeRecipientTotalColl
        ) {
            log = log
                .concat("feeRecipientTotalColl\t")
                .concat(ebtcBefore.feeRecipientTotalColl.pretty())
                .concat("\t")
                .concat(ebtcAfter.feeRecipientTotalColl.pretty())
                .concat("\n");
        }
        if (ebtcBefore.actorColl != ebtcAfter.actorColl) {
            log = log
                .concat("actorColl\t\t\t\t")
                .concat(ebtcBefore.actorColl.pretty())
                .concat("\t")
                .concat(ebtcAfter.actorColl.pretty())
                .concat("\n");
        }
        if (ebtcBefore.actorEbtc != ebtcAfter.actorEbtc) {
            log = log
                .concat("actorEbtc\t\t\t\t")
                .concat(ebtcBefore.actorEbtc.pretty())
                .concat("\t")
                .concat(ebtcAfter.actorEbtc.pretty())
                .concat("\n");
        }
        if (ebtcBefore.actorCdpCount != ebtcAfter.actorCdpCount) {
            log = log
                .concat("actorCdpCount\t\t\t")
                .concat(ebtcBefore.actorCdpCount.pretty())
                .concat("\t")
                .concat(ebtcAfter.actorCdpCount.pretty())
                .concat("\n");
        }
        if (ebtcBefore.cdpColl != ebtcAfter.cdpColl) {
            log = log
                .concat("cdpColl\t\t\t\t")
                .concat(ebtcBefore.cdpColl.pretty())
                .concat("\t")
                .concat(ebtcAfter.cdpColl.pretty())
                .concat("\n");
        }
        if (ebtcBefore.cdpDebt != ebtcAfter.cdpDebt) {
            log = log
                .concat("cdpDebt\t\t\t\t")
                .concat(ebtcBefore.cdpDebt.pretty())
                .concat("\t")
                .concat(ebtcAfter.cdpDebt.pretty())
                .concat("\n");
        }
        if (
            ebtcBefore.liquidatorRewardShares !=
            ebtcAfter.liquidatorRewardShares
        ) {
            log = log
                .concat("liquidatorRewardShares\t\t")
                .concat(ebtcBefore.liquidatorRewardShares.pretty())
                .concat("\t")
                .concat(ebtcAfter.liquidatorRewardShares.pretty())
                .concat("\n");
        }
        if (ebtcBefore.sortedCdpsSize != ebtcAfter.sortedCdpsSize) {
            log = log
                .concat("sortedCdpsSize\t\t\t")
                .concat(ebtcBefore.sortedCdpsSize.pretty(0))
                .concat("\t\t\t")
                .concat(ebtcAfter.sortedCdpsSize.pretty(0))
                .concat("\n");
        }
        if (ebtcBefore.cdpStatus != ebtcAfter.cdpStatus) {
            log = log
                .concat("cdpStatus\t\t\t")
                .concat(ebtcBefore.cdpStatus.pretty(0))
                .concat("\t\t\t")
                .concat(ebtcAfter.cdpStatus.pretty(0))
                .concat("\n");
        }
        if (ebtcBefore.tcr != ebtcAfter.tcr) {
            log = log
                .concat("tcr\t\t\t\t")
                .concat(ebtcBefore.tcr.pretty())
                .concat("\t")
                .concat(ebtcAfter.tcr.pretty())
                .concat("\n");
        }
        if (ebtcBefore.newTcr != ebtcAfter.newTcr) {
            log = log
                .concat("newTcr\t\t\t\t")
                .concat(ebtcBefore.newTcr.pretty())
                .concat("\t")
                .concat(ebtcAfter.newTcr.pretty())
                .concat("\n");
        }
        if (ebtcBefore.ebtcTotalSupply != ebtcAfter.ebtcTotalSupply) {
            log = log
                .concat("ebtcTotalSupply\t\t\t")
                .concat(ebtcBefore.ebtcTotalSupply.pretty())
                .concat("\t")
                .concat(ebtcAfter.ebtcTotalSupply.pretty())
                .concat("\n");
        }
        if (ebtcBefore.ethPerShare != ebtcAfter.ethPerShare) {
            log = log
                .concat("ethPerShare\t\t\t")
                .concat(ebtcBefore.ethPerShare.pretty())
                .concat("\t")
                .concat(ebtcAfter.ethPerShare.pretty())
                .concat("\n");
        }
        if (ebtcBefore.isRecoveryMode != ebtcAfter.isRecoveryMode) {
            log = log
                .concat("isRecoveryMode\t\t\t")
                .concat(ebtcBefore.isRecoveryMode.pretty())
                .concat("\t")
                .concat(ebtcAfter.isRecoveryMode.pretty())
                .concat("\n");
        }
        if (
            ebtcBefore.lastGracePeriodStartTimestamp !=
            ebtcAfter.lastGracePeriodStartTimestamp
        ) {
            log = log
                .concat("lastGracePeriodStartTimestamp\t")
                .concat(ebtcBefore.lastGracePeriodStartTimestamp.pretty())
                .concat("\t")
                .concat(ebtcAfter.lastGracePeriodStartTimestamp.pretty())
                .concat("\n");
        }
        if (
            ebtcBefore.lastGracePeriodStartTimestampIsSet !=
            ebtcAfter.lastGracePeriodStartTimestampIsSet
        ) {
            log = log
                .concat("lastGracePeriodStartTimestampIsSet\t")
                .concat(ebtcBefore.lastGracePeriodStartTimestampIsSet.pretty())
                .concat("\t")
                .concat(ebtcAfter.lastGracePeriodStartTimestampIsSet.pretty())
                .concat("\n");
        }
        if (ebtcBefore.hasGracePeriodPassed != ebtcAfter.hasGracePeriodPassed) {
            log = log
                .concat("hasGracePeriodPassed\t\t")
                .concat(ebtcBefore.hasGracePeriodPassed.pretty())
                .concat("\t\t\t")
                .concat(ebtcAfter.hasGracePeriodPassed.pretty())
                .concat("\n");
        }
        if (
            ebtcBefore.systemDebtRedistributionIndex !=
            ebtcAfter.systemDebtRedistributionIndex
        ) {
            log = log
                .concat("systemDebtRedistributionIndex\t\t")
                .concat(ebtcBefore.systemDebtRedistributionIndex.pretty())
                .concat("\t")
                .concat(ebtcAfter.systemDebtRedistributionIndex.pretty())
                .concat("\n");
        }
    }
}
