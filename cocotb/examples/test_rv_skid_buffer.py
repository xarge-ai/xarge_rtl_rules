# SPDX-License-Identifier: LicenseRef-XARGE-Proprietary
# SPDX-FileCopyrightText: © 2025 Xarge.AI. All rights reserved.
# Xarge.AI Internal – Confidential. Unauthorized use, copying, or distribution is prohibited.

"""
Test Suite: rv_skid_buffer

Description:
    Cocotb-based testbench for verifying ready-valid skid buffer implementations.
    Tests both basic functionality and random transaction sequences.

Test Cases:
    1. test_rv_skid_buffer: Basic single transaction test
       - Verifies data passes through buffer correctly
       - Checks basic handshaking protocol

    2. test_rv_skid_buffer_random: Sequential transaction test
       - Sends 10 sequential data values
       - Verifies data ordering and integrity
       - Tests sustained operation

Features:
    - Uses cocotbext-axi stream library for ready-valid protocol handling
    - Configurable clock period (4ns default)
    - Active-low reset protocol
    - Automated data verification
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer
from cocotbext.axi.stream import define_stream


@cocotb.test()
async def test_rv_skid_buffer(dut):
    """
    Basic functionality test for skid buffer.

    Test Procedure:
        1. Initialize stream interfaces
        2. Start clock generation
        3. Apply reset sequence
        4. Send single data transaction (0xa5)
        5. Receive and verify data

    Expected Result:
        Output data should match input data (0xa5)
    """
    # Define the stream interface for the DataBus
    DataBus, DataTransaction, DataSource, DataSink, DataMonitor = define_stream(
        "Data",
        signals=["data", "valid", "ready"]
    )

    # Initialize the DataSource (upstream) and DataSink (downstream)
    # Maps DUT signals using prefix matching (rv_in_*, rv_out_*)
    data_in = DataSource(
        DataBus.from_prefix(dut, "rv_in"), dut.clk, dut.rst_n,
        reset_active_level=False
    )
    data_out = DataSink(
        DataBus.from_prefix(dut, "rv_out"), dut.clk, dut.rst_n,
        reset_active_level=False
    )

    # Generate clock with a period of 4 ns
    cocotb.start_soon(Clock(dut.clk, 4, "ns").start())

    # Apply reset
    dut.rst_n.value = 0
    await Timer(10, "ns")  # Hold reset for 10 ns
    dut.rst_n.value = 1
    await Timer(10, "ns")  # Wait for design to stabilize

    # Create and send test data transaction
    data = DataTransaction(data=0xa5)
    await data_in.send(data)  # Send data through ready-valid interface

    # Receive and verify data from output
    datao = await data_out.recv()

    # Assertion: Verify data integrity through buffer
    assert datao.data == data.data


@cocotb.test()
async def test_rv_skid_buffer_random(dut):
    """
    Sequential multi-transaction test for skid buffer.

    Test Procedure:
        1. Initialize stream interfaces
        2. Start clock generation
        3. Apply reset sequence
        4. Send 10 sequential transactions (data = 0 to 9)
        5. Receive all transactions
        6. Verify data ordering and values

    Expected Result:
        - All transactions should pass through in order
        - Data values should match: received[i] == sent[i] for i in [0..9]
        - Tests buffer behavior under sustained load
    """
    # Define the stream interface for the DataBus
    # Creates transaction types compatible with ready-valid protocol
    DataBus, DataTransaction, DataSource, DataSink, DataMonitor = define_stream(
        "Data",
        signals=["data", "valid", "ready"]
    )

    # Initialize the DataSource (upstream) and DataSink (downstream)
    # Maps DUT signals using prefix matching (rv_in_*, rv_out_*)
    data_in = DataSource(
        DataBus.from_prefix(dut, "rv_in"), dut.clk, dut.rst_n,
        reset_active_level=False
    )
    data_out = DataSink(
        DataBus.from_prefix(dut, "rv_out"), dut.clk, dut.rst_n,
        reset_active_level=False
    )

    # Generate clock with a period of 4 ns (250 MHz)
    cocotb.start_soon(Clock(dut.clk, 4, "ns").start())

    # Apply reset sequence
    # Active-low reset: assert (0), wait, deassert (1), wait for stability
    dut.rst_n.value = 0
    await Timer(10, "ns")  # Hold reset for 10 ns

    dut.rst_n.value = 1
    await Timer(10, "ns")  # Wait for design to stabilize

    # Send multiple sequential transactions
    # This tests buffer behavior under sustained load
    for i in range(10):
        data = DataTransaction(data=i)
        await data_in.send(data)  # Send transaction through ready-valid interface

    # Receive and verify all transactions
    # Verify data ordering is preserved and values are correct
    for i in range(10):
        datao = await data_out.recv()
        assert datao.data == i, f"Data mismatch: expected {i}, got {datao.data}"

    # Final wait to ensure all signals settle
    await Timer(10, "ns")
