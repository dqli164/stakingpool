pragma solidity ^0.8.20;

contract ScriptGenerator {
    // 这个函数将返回调用Voting合约upgrade函数的bytes参数
    function generateUpgradeCallData(
        address proxyAddress,
        address proxyAdminAddress,
        address newImplementation
    ) public pure returns (bytes memory) {
        // Voting合约中upgrade函数的函数选择器
        bytes4 selector = bytes4(keccak256("upgrade(address,address,address)"));

        // 编码调用数据
        return abi.encodeWithSelector(selector, proxyAddress, proxyAdminAddress, newImplementation);
    }
}
