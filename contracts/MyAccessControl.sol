// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract MyAccessControl is AccessControl {
    function revokeRole(bytes32 role, address account) public override {
        require(
            role != DEFAULT_ADMIN_ROLE,
            "ModifiedAccessControl: cannot revoke default admin role"
        );

        super.revokeRole(role, account);
    }
}