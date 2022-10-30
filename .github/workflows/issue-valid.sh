#!/bin/bash
REPO=$1
REPO_OWNER=$2
PR_NUMBER=$3
REPO_NAME="${REPO/${REPO_OWNER}\//}"
echo "REPO_OWNER:"$REPO_OWNER
echo "REPO_NAME:"$REPO_NAME
echo "PR_NUMBER:"$PR_NUMBER

closingIssuesReferences="$(
gh api graphql -f query='
{
  repository(owner: "'$REPO_OWNER'", name: "'$REPO_NAME'") {
    pullRequest(number: '$PR_NUMBER') {
      id
      closingIssuesReferences (first: 10) {
        edges {
          node {
            title
            number
          }
        }
      }
    }
  }
}' --jq '.data.repository.pullRequest.closingIssuesReferences.edges'
)"

echo "closingIssuesReferences:"$closingIssuesReferences

if [[ "$closingIssuesReferences" == "[]" ]];then
  echo "PR has no Issues References"
  exit 1
else
  echo "PR has Issues References"
  exit 0
fi