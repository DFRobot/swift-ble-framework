//
//  DFBle.swift
//  DFBle
//
//  Created by LeeYaping on 15/9/2.
//  Copyright (c) 2015年 lisper. All rights reserved.
//

import Foundation
import CoreBluetooth


/**
*  easy protocol, to use ble
*/
@objc public protocol BleProtocol {
    optional func didDiscover (name:String, rssi:NSNumber)
    optional func didConnect (name:String)
    optional func didDisconnect ()
    optional func didBleReady()
    optional func didReadRSSI (rssi:NSNumber)
}


public class DFBle:NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    public static let sharedInstance = DFBle ()
    
    struct peripheralWithRssi {
        var RSSI: NSNumber
        var peripheral :CBPeripheral
    }
    
    var bright:UInt8 = 255
    var color:UInt8 = 0
    
    public var delegate :BleProtocol?
    let DFUUID :CBUUID = CBUUID(string: "DFB0")
    var rescanTimer :NSTimer?
    var rssiTimer :NSTimer?
    var centralManager :CBCentralManager!
    var myperipheral :CBPeripheral?
    var mychar :CBCharacteristic?
    var myservice :CBService?
    var peripherals :[peripheralWithRssi]!
    
    var isKeepConnect = true
    var isConnect :Bool = false
    var isScanning :Bool = false
    
    private override init () {
        super.init ()
        print ("shared instance")
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
        peripherals = [peripheralWithRssi]()
    }
    
    /*
    override init () {
        super.init ()
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
        peripherals = [peripheralWithRssi]()
    }
    */
    private convenience init (delegate: BleProtocol) {
        self.init ()
        self.delegate = delegate
    }
  
    
    
    public func beginScan () {
        if isScanning == false {
            isKeepConnect = true
            self.centralManager.scanForPeripheralsWithServices([DFUUID], options: nil)
            rescanTimer = NSTimer.scheduledTimerWithTimeInterval(2, target: self, selector: "updateScan", userInfo: nil, repeats: true)
            isScanning = true
        }
    }
    
    /**
    stop scan ble device
    */
    public func breakScan () {
        rescanTimer?.invalidate()
        rescanTimer = nil
        centralManager.stopScan()
        isScanning = false
    }
    
    public func disConnect () {
        isKeepConnect = false
        centralManager.cancelPeripheralConnection(myperipheral!)
    }
    
    /**
    rescan ble device every 2 seconds
    */
    func updateScan () {
        if let p = getMaxPeripheral() {
            myperipheral = p
            connect(myperipheral!)
        } else {
            print ("rescan")
            self.centralManager.scanForPeripheralsWithServices([DFUUID], options: nil)
        }
    }
    
    /**
    connect a peripheral
    
    - parameter peripheral: that rssi is best
    */
    func connect (peripheral:CBPeripheral) {
        myperipheral = peripheral
        centralManager.stopScan()
        isScanning = false
        self.rescanTimer?.invalidate()
        self.rescanTimer = nil
        centralManager.connectPeripheral(peripheral, options: nil)
    }
    
    /**
    send one byte to connected peripheral
    
    - parameter value: one byte data will send
    */
    public func sendByte (value :UInt8) {
        var myvalue = value
        let data = NSData(bytes: &myvalue, length: 1)
        myperipheral?.writeValue(data, forCharacteristic: mychar!, type: CBCharacteristicWriteType.WithoutResponse)
    }
    
    /**
    send String to connected peripheral
    
    - parameter value: -> a string will send
    */
    public func sendString (value :String) {
        if value.lengthOfBytesUsingEncoding(NSASCIIStringEncoding) == 0 {
            return
        }
        let data = value.dataUsingEncoding(NSASCIIStringEncoding, allowLossyConversion: true)
        print ("data: \(data)")
        myperipheral?.writeValue(data!, forCharacteristic: mychar!, type: CBCharacteristicWriteType.WithoutResponse)
    }
    
    /**
    send data to control a car
    
    - parameter left:    left speed
    - parameter right:   right speed
    */
    func sendRunCommand (left left:Int8, right:Int8) {
        let cmd :UInt8 = 0x10
        let cmdString = String(format: "$%02X%02X%02X\r", cmd, UInt8(bitPattern: left) , UInt8(bitPattern: right))
        print("cmd=\(cmdString.lengthOfBytesUsingEncoding(NSASCIIStringEncoding)):\(cmdString)")
        sendString(cmdString)
    }


    
    @objc public func centralManagerDidUpdateState(central: CBCentralManager) {
        if centralManager.state == .PoweredOn {
            print ("ble opened")
        } else {
            print ("ble open error")
        }
    }
    
    public func centralManager(central: CBCentralManager, didDiscoverPeripheral peripheral: CBPeripheral, advertisementData: [String : AnyObject], RSSI: NSNumber) {
        //println ("didDiscoverPeripheral ")
        print ("name=\(peripheral.name)  RSSI=\(Int32(RSSI.intValue))")
        if peripheral.name == "car_007" {
            connect(peripheral)
        }
        if RSSI.integerValue > -50 && RSSI.integerValue < -10 {
            appendPeripheral(peripheral, RSSI: RSSI)
        }
        delegate?.didDiscover?(peripheral.name!, rssi: RSSI)
    }
    
    /**
    append new find peripheral to peripherals and update rssi
    
    - parameter peripheral:
    - parameter RSSI:
    */
    func appendPeripheral (peripheral :CBPeripheral, RSSI :NSNumber) {
        for var p=1; p < self.peripherals.count; p++  {
            if self.peripherals[p].peripheral == peripheral {
                self.peripherals[p].RSSI = RSSI
                return
            }
        }
        self.peripherals.append(peripheralWithRssi(RSSI: RSSI, peripheral: peripheral))
    }
    
    /**
    return the max rssi peripheral tin peripherals
    
    - returns: peripheral with best rssi or nil
    */
    func getMaxPeripheral () -> CBPeripheral? {
        if self.peripherals.count == 0 {
            return nil
        }
        var max :NSNumber = self.peripherals[0].RSSI
        var maxPeripheral :CBPeripheral = self.peripherals[0].peripheral
        
        for p in self.peripherals {
            if p.RSSI.integerValue > max.integerValue {
                max = p.RSSI
                maxPeripheral = p.peripheral
            }
        }
        return maxPeripheral
    }
    
    public func centralManager(central: CBCentralManager, didConnectPeripheral peripheral: CBPeripheral) {
        //println ("didConnectPeripheral ")
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        peripheral.readRSSI()
        rescanTimer?.invalidate()
        rescanTimer = nil
        delegate?.didConnect?(peripheral.name!)
    }
    
    public func centralManager(central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: NSError?) {
        //println ("didDisconnectPeripheral ")
        isConnect = false
        rssiTimer?.invalidate()
        rssiTimer = nil
        rescanTimer?.invalidate()
        if isKeepConnect == true {
            centralManager.connectPeripheral(myperipheral!, options: nil)
        }
        delegate?.didDisconnect?()
    }
    
    public func peripheral(peripheral: CBPeripheral, didDiscoverServices error: NSError?) {
        //println ("didDiscoverServices ")
        if (peripheral.services![1] ).UUID.UUIDString == "DFB0" {
            //println ("get DFB0")
            myservice = peripheral.services![1]// as? CBService
            peripheral.discoverCharacteristics(nil, forService: peripheral.services![1])// as! CBService)
        }
        
    }
    
    public func peripheral(peripheral: CBPeripheral, didDiscoverCharacteristicsForService service: CBService, error: NSError?) {
        //println ("didDiscoverCharacteristicsForService ")
        let char = (service.characteristics![0]) //as! CBCharacteristic)
        if char.UUID.UUIDString == "DFB1" {
            //println ("get DFB1")
            mychar = char
            myperipheral?.setNotifyValue(true, forCharacteristic: mychar!)
            isConnect = true
            rssiTimer = NSTimer.scheduledTimerWithTimeInterval(1, target: self, selector: "updateRSSI", userInfo: nil, repeats: true)
            delegate?.didBleReady?()
        }
    }
    
    /**
    read rssi every seconds
    */
    func updateRSSI () {
        myperipheral?.readRSSI()
    }
    
    public func peripheral(peripheral: CBPeripheral, didUpdateNotificationStateForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        //println ("didUpdateNotificationStateForCharacteristic ")
    }
    
    //
    public func peripheral(peripheral: CBPeripheral, didUpdateValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        print ("didUpdateValueForCharacteristic")
        let str = NSString(data: characteristic.value!, encoding: NSASCIIStringEncoding)
        //var str = NSString(data: characteristic.value(), encoding: NSASCIIStringEncoding)
        if str != nil {
            print ("read:(\(str!.length)) \(str!)")
        }
    }
    
    public func peripheral(peripheral: CBPeripheral, didWriteValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        //println ("didWriteValueForCharacteristic ")
    }
    
    /*
    func peripheralDidUpdateRSSI(peripheral: CBPeripheral!, error: NSError!) {
    rssiLabel.text = peripheral.RSSI.stringValue
    }
    */
    
    func peripheral(peripheral: CBPeripheral!, didReadRSSI RSSI: NSNumber!, error: NSError!) {
        //      println ("didReadRSSI ")
        delegate?.didReadRSSI?(RSSI)
    }
    
}
