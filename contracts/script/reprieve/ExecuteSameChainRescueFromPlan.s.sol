// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {RescueExecutor} from "../../src/reprieve/RescueExecutor.sol";
import {ReprieveTypes} from "../../src/reprieve/libs/ReprieveTypes.sol";

/**
 * @title ExecuteSameChainRescueFromPlan
 * @notice Executes a same-chain rescue plan from env-provided fields (no position seeding).
 * @dev Intended as manual fallback when CRE runtime cannot submit write tx directly.
 */
contract ExecuteSameChainRescueFromPlan is Script {
    function run() external {
        uint256 ownerPk = vm.envUint("PRIVATE_KEY");
        uint256 workflowPk = vm.envOr("WORKFLOW_PRIVATE_KEY", ownerPk);
        address owner = vm.addr(ownerPk);
        address workflow = vm.addr(workflowPk);

        address rescueExecutorAddr = vm.envAddress("RESCUE_EXECUTOR");
        address user = vm.envAddress("RESCUE_USER");
        address sourceAdapter = vm.envAddress("SOURCE_ADAPTER");
        address targetAdapter = vm.envAddress("TARGET_ADAPTER");
        address collateralAsset = vm.envAddress("STEP_COLLATERAL_ASSET");
        address debtAsset = vm.envAddress("STEP_DEBT_ASSET");

        uint256 collateralAmount = vm.envUint("STEP_COLLATERAL_AMOUNT");
        uint256 debtAmount = vm.envOr("STEP_DEBT_AMOUNT", uint256(0));
        uint256 deadlineSeconds = vm.envOr("DEADLINE_SECONDS", uint256(3600));
        uint256 maxFee = vm.envOr("MAX_FEE_WEI", uint256(0));
        bool setWorkflowAuth = vm.envOr("SET_WORKFLOW_AUTH", true);

        string memory modeRaw = vm.envOr("RESCUE_MODE", string("TOP_UP"));
        ReprieveTypes.RescueMode mode = _parseMode(modeRaw);

        bytes32 fallbackExecId =
            keccak256(abi.encodePacked("same-chain-plan-exec", block.chainid, user, modeRaw, block.timestamp));
        bytes32 execId = vm.envOr("EXECUTION_ID", fallbackExecId);

        RescueExecutor executor = RescueExecutor(payable(rescueExecutorAddr));

        ReprieveTypes.RescueStep[] memory steps = new ReprieveTypes.RescueStep[](1);
        steps[0] = ReprieveTypes.RescueStep({
            stepIndex: 0,
            sourceAdapter: sourceAdapter,
            targetAdapter: targetAdapter,
            collateralAsset: collateralAsset,
            debtAsset: debtAsset,
            collateralAmount: collateralAmount,
            debtAmount: debtAmount,
            isCrossChain: false,
            targetChain: 0
        });

        ReprieveTypes.RescuePlan memory plan = ReprieveTypes.RescuePlan({
            execId: execId,
            user: user,
            mode: mode,
            steps: steps,
            deadline: block.timestamp + deadlineSeconds,
            maxFee: maxFee
        });

        console.log("Executing same-chain rescue plan");
        console.log("Chain ID:", block.chainid);
        console.log("Owner:", owner);
        console.log("Workflow:", workflow);
        console.log("Executor:", rescueExecutorAddr);
        console.log("User:", user);
        console.log("ExecId:", vm.toString(execId));
        console.log("Mode:", modeRaw);
        console.log("SourceAdapter:", sourceAdapter);
        console.log("TargetAdapter:", targetAdapter);
        console.log("CollateralAsset:", collateralAsset);
        console.log("DebtAsset:", debtAsset);
        console.log("CollateralAmount:", collateralAmount);
        console.log("DebtAmount:", debtAmount);

        if (setWorkflowAuth) {
            vm.startBroadcast(ownerPk);
            executor.setAuthorizedWorkflow(workflow, true);
            vm.stopBroadcast();
        }

        vm.startBroadcast(workflowPk);
        bool ok = executor.executeRescue(plan);
        vm.stopBroadcast();

        console.log("executeRescue success:", ok);
        console.log("Rescue status enum:", uint256(executor.getRescueStatus(execId)));
    }

    function _parseMode(string memory raw) internal pure returns (ReprieveTypes.RescueMode) {
        bytes32 modeHash = keccak256(bytes(raw));
        if (modeHash == keccak256(bytes("TOP_UP"))) {
            return ReprieveTypes.RescueMode.TOP_UP;
        }
        if (modeHash == keccak256(bytes("REPAY"))) {
            return ReprieveTypes.RescueMode.REPAY;
        }
        revert("ExecuteSameChainRescueFromPlan: RESCUE_MODE must be TOP_UP or REPAY");
    }
}
