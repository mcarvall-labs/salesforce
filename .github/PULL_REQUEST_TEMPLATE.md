## Summary

<!-- What changed and why. -->

<!--
CI validates/deploys Apex with RunSpecifiedTests, scoped to whatever Apex test
classes are present in this PR's delta. If a changed Apex class or trigger is
covered only by a test class that is NOT part of this PR's delta, add a
"Salesforce test classes" heading (H2, i.e. two # marks) below and list that
test class's name in a bullet. Multiple classes can go on one bullet or several,
separated by spaces and/or commas, e.g.:

  - FooControllerTest BarTriggerHandlerTest, BazServiceTest

Otherwise the pipeline fails closed for missing coverage. See
docs/SALESFORCE_DELIVERY.md. Delete this comment and the heading if they don't
apply.
-->

## Test plan

<!-- How you verified this change. -->
