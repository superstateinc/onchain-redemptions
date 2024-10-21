// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract TestChainlinkDataFeedOracle {
    uint80 public roundId;
    int256 public answer;
    uint256 public startedAt;
    uint256 public updatedAt;
    uint80 public answeredInRound;

    constructor(uint80 _roundId, int256 _answer, uint256 _startedAt, uint256 _updatedAt, uint80 _answeredInRound) {
        update({
            _roundId: _roundId,
            _answer: _answer,
            _startedAt: _startedAt,
            _updatedAt: _updatedAt,
            _answeredInRound: _answeredInRound
        });
    }

    function update(uint80 _roundId, int256 _answer, uint256 _startedAt, uint256 _updatedAt, uint80 _answeredInRound)
        public
    {
        roundId = _roundId;
        answer = _answer;
        startedAt = _startedAt;
        updatedAt = _updatedAt;
        answeredInRound = _answeredInRound;
    }

    function decimals() external pure returns (uint8) {
        return 6;
    }

    function description() external pure returns (string memory) {
        return "hi";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    //    function getRoundData(uint80 _roundId)
    //        external
    //        view
    //        returns (uint80 _roundId, int256 _answer, uint256 _startedAt, uint256 _updatedAt, uint80 _answeredInRound)
    //    {
    //        _roundId = roundId;
    //        _answer = answer;
    //        _startedAt = startedAt;
    //        _updatedAt = updatedAt;
    //        _answeredInRound = answeredInRound;
    //    }

    function latestRoundData()
        external
        view
        returns (uint80 _roundId, int256 _answer, uint256 _startedAt, uint256 _updatedAt, uint80 _answeredInRound)
    {
        _roundId = roundId;
        _answer = answer;
        _startedAt = startedAt;
        _updatedAt = updatedAt;
        _answeredInRound = answeredInRound;
    }
}
