#!/bin/bash

# Initialize git SSH agent and add key
eval "$(ssh-agent -s)" && ssh-add ~/.ssh/gh_key 