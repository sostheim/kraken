#encoding: utf-8
Feature: Make sure we have the correct kubernetes resources
  In order to verify that cluster came up correctly
  As kraken developer
  I should be able to run these scenarios and see the correct exit code and kubectl output

  Scenario: Getting nodes
    When I kubectl nodes
    Then the exit status should eventually be 0
    And the output should eventually match:
      """
      .*
      .*Ready
      .*Ready
      """

  Scenario: Getting kube-system services
    When I kubectl system services
    Then the exit status should eventually be 0
    And the output should eventually match:
      """
      .*
      heapster.*
      kube-dns.*
      kubedash.*
      monitoring-grafana.*
      monitoring-influxdb.*
      """

  Scenario: Getting kube-system pods
    When I kubectl system pods
    Then the exit status should eventually be 0
    And the output should eventually match:
      """
      .*
      heapster.*Running.*
      kube-dns.*Running.*
      kubedash.*Running.*
      monitoring-influxdb-grafana.*Running.*
      """

  Scenario: Getting default services
    When I kubectl services
    Then the exit status should eventually be 0
    And the output should eventually match:
      """
      .*
      kubernetes.*
      prometheus.*
      """
