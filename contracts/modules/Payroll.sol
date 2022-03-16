//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import 'hardhat/console.sol';
import '@openzeppelin/contracts/utils/Strings.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {Module} from '../core/Module.sol';
import {IMembership} from '../interfaces/IMembership.sol';

contract Payroll is Module {
    using Strings for uint256;
    using Address for address payable;

    enum PayrollType {
        Salary,
        Bonus,
        Commission,
        Dividend,
        Other
    }

    enum PayrollPeriod {
        Monthly,
        Quarterly,
        Yearly,
        OneTime
    }

    struct PayrollInTokens {
        address[] tokens;
        uint256[] amounts;
    }

    struct PayrollDetail {
        uint256 amount;
        PayrollType paytype;
        PayrollPeriod period;
        PayrollInTokens tokens;
    }

    event PayrollAdded(uint256 indexed memberId, PayrollDetail payroll);

    // MemberId => (PayrollPeriod => PayrollDetail[])
    mapping(uint256 => mapping(PayrollPeriod => PayrollDetail[])) private _payrolls;

    constructor(
        address membership,
        uint256[] memory operators,
        uint256 delay
    ) Module('Payroll', 'Payroll Contract V1', membership, operators, delay) {}

    function AddPayroll(uint256 memberId, PayrollDetail calldata payroll) public onlyOperator {
        _payrolls[memberId][payroll.period].push(payroll);
        emit PayrollAdded(memberId, payroll);
    }

    function GetPayroll(uint256 memberId, PayrollPeriod period)
        public
        view
        returns (PayrollDetail[] memory)
    {
        return _payrolls[memberId][period];
    }

    function schedulePayroll(uint256 memberId, PayrollPeriod period)
        public
        onlyOperator
        returns (bytes32 _proposalId)
    {
        PayrollDetail[] memory payrolls = GetPayroll(memberId, period);
        address[] memory targets = new address[](payrolls.length);
        uint256[] memory values;
        bytes[] memory calldatas;
        string memory description = string(
            abi.encodePacked(
                'Payroll for ',
                memberId.toString(),
                '(',
                block.timestamp.toString(),
                ')'
            )
        );

        address memberWallet = getAddressByMemberId(memberId);

        for (uint256 i = 0; i < payrolls.length; i++) {
            PayrollDetail memory payroll = payrolls[i];
            targets[i] = address(this);
            values[i] = payroll.amount;

            // TODO: use byte4(func selector) to reduce the size of calldata
            calldatas[i] = abi.encodeWithSignature(
                'execTransfer(address,address[],uint256[])',
                memberWallet,
                payroll.tokens.tokens,
                payroll.tokens.amounts
            );
        }

        _proposalId = propose(targets, values, calldatas, description);
    }

    function execTransfer(
        address payable account,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external payable onlyTimelock {
        if (msg.value > 0) {
            account.sendValue(msg.value);
        }

        address treasury = IMembership(membership).treasury();

        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).transferFrom(treasury, address(account), amounts[i]);
        }
    }
}
