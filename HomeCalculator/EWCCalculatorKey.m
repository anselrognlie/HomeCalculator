//
//  EWCCalculatorKey.m
//  HomeCalculator
//
//  Created by Ansel Rognlie on 11/5/19.
//  Copyright © 2019 Ansel Rognlie. All rights reserved.
//

//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.

#import <Foundation/Foundation.h>
#import "EWCCalculatorKey.h"

BOOL EWCCalculatorKeyIsBinaryOp(EWCCalculatorKey key) {
  switch (key) {
    // the binary op keys are add, subtract, multiply, and divide
    case EWCCalculatorAddKey:
    case EWCCalculatorSubtractKey:
    case EWCCalculatorMultiplyKey:
    case EWCCalculatorDivideKey:
      return YES;

    default:
      return NO;
  }
}

BOOL EWCCalculatorKeyIsRateKey(EWCCalculatorKey key) {
  switch (key) {
    // the tax rate keys are rate, tax plus, and tax minus
    case EWCCalculatorRateKey:
    case EWCCalculatorTaxPlusKey:
    case EWCCalculatorTaxMinusKey:
      return YES;

    default:
      return NO;
  }
}
