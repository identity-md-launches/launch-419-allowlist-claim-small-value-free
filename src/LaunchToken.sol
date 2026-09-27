// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Fixed-supply launch artifact; AllowlistClaim does not use or distribute this token.
contract LaunchToken {
    string public constant name = "Allowlist Claim";
    string public constant symbol = "ALLOW";
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 1_000_000_000 * 10 ** 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InvalidSpender(address spender);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    constructor() {
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        if (spender == address(0)) revert ERC20InvalidSpender(spender);
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 available = allowance[from][msg.sender];
        if (available != type(uint256).max) {
            if (available < amount) revert ERC20InsufficientAllowance(msg.sender, available, amount);
            unchecked {
                allowance[from][msg.sender] = available - amount;
            }
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        if (from == address(0)) revert ERC20InvalidSender(from);
        if (to == address(0)) revert ERC20InvalidReceiver(to);
        uint256 available = balanceOf[from];
        if (available < amount) revert ERC20InsufficientBalance(from, available, amount);
        unchecked {
            balanceOf[from] = available - amount;
            // The conserved supply bounds the sum, including transfers to the sender itself.
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }
}
