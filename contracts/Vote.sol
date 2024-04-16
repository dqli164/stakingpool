// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface Proxy {
  function upgradeTo(address newImplementation) external;
}

contract Voter {
  function upgrade(address proxyAddress, address implementationAddress) public {
    Proxy proxy = Proxy(proxyAddress);
    proxy.upgradeTo(implementationAddress);
  }
}
