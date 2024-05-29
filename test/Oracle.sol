// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

contract Oracle {
    constructor() {}

    function decimals() external view returns (uint8) {
        return 18;
    }

    function description() external view returns (string memory) {
        return "hi";
    }

    function version() external view returns (uint256) {
        return 1;
    }

    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = 1;
        answer = 10_192_577_000_000_000_000; // 18 decimals
        startedAt = 1_716_994_000;
        updatedAt = 1_716_994_030;
        answeredInRound = 1;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = 1;
        answer = 10_192_577_000_000_000_000; // 18 decimals
        startedAt = 1_716_994_000;
        updatedAt = 1_716_994_030;
        answeredInRound = 1;
    }
}
