// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

abstract contract MembersOnly {
    /*************
     * Modifiers *
     *************/
    modifier onlyOwner() {
        require(msg.sender == owner, "E0");
        _;
    }

    modifier onlyAuthorizedUser() {
        require(_authorizedUsers[msg.sender], "No auth.");
        _;
    }

    /**************
     * Properties *
     **************/
    address immutable public owner;

    /******************
     * Private Fields *
     ******************/
    mapping(address user => bool isAuthorized) private _authorizedUsers;

    constructor() {
        owner = msg.sender;
    }

    /// @notice Adds an authorized user to the contract.
    function addAuthorizedUser(address user) external onlyOwner {
        _authorizedUsers[user] = true;
    }

    /// @notice Adds a list of authorized users to the contract.
    function addAuthorizedUsers(address[] memory users) external onlyOwner {
        for (uint16 i = 0; i < users.length; i++) _authorizedUsers[users[i]] = true;
    }

    /// @notice Checks if a user is authorized.
    function isAuthorized() public view returns (bool) {
        return _isAuthorized(msg.sender);
    }

    /// @notice Checks if a user is authorized.
    /// @param user The address of the user to check.
    function isAuthorized(address user) external view onlyOwner returns (bool) {
        return _isAuthorized(user);
    }

    /// @notice Checks if a user is authorized.
    /// @param user The address of the user to check.
    function _isAuthorized(address user) internal view returns (bool) {
        return _authorizedUsers[user];
    }
}