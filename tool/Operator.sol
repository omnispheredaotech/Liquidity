
// SPDX-License-Identifier: SimPL-2.0
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Operator is Ownable {
    mapping (address => bool) private operators;
    
    // event for EVM logging
    event OperatorAdd(address indexed oldOperator);
    event OperatorDel(address indexed oldOperator);
    
    // modifier to check if caller is operator
    modifier onlyOperator() {
        // If the first argument of 'require' evaluates to 'false', execution terminates and all
        // changes to the state and to Ether balances are reverted.
        // This used to consume all gas in old EVM versions, but not anymore.
        // It is often a good idea to use 'require' to check if functions are called correctly.
        // As a second argument, you can also provide an explanation about what went wrong.
        require(operators[msg.sender], "Caller is not operator");
        _;
    }
    
    /**
     * @dev Set contract deployer as operator
     */
    constructor() {
        operators[msg.sender] = true; // 'msg.sender' is sender of current call, contract deployer for a constructor
        emit OperatorAdd(msg.sender);
    }

    /**
     * @dev Add operator
     * @param newOperator address of new operator
     */
    function addOperator(address newOperator) public onlyOwner {
        operators[newOperator] = true;
        emit OperatorAdd(newOperator);
    }

    function delOperator(address operator) public onlyOwner {
        operators[operator] = false;
        emit OperatorDel(operator);
    }

    /**
     * @dev Return if a address is opreator
     * @return bool
     */
    function isOperator(address account) external view returns (bool) {
        return operators[account];
    }
}