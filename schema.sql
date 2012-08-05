- phpMyAdmin SQL Dump
-- version 3.3.3
-- http://www.phpmyadmin.net
--
-- Host: localhost
-- Generation Time: Aug 01, 2012 at 01:18 AM
-- Server version: 5.0.51
-- PHP Version: 5.2.6-1+lenny3

SET SQL_MODE="NO_AUTO_VALUE_ON_ZERO";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;

--
-- Database: `sourcemod_beta`
--

-- --------------------------------------------------------

--
-- Table structure for table `jump`
--

CREATE TABLE IF NOT EXISTS `jump` (
  `steamid` varchar(64) NOT NULL,
  `map` varchar(64) NOT NULL,
  `class` tinyint(4) NOT NULL,
  `id` tinyint(4) NOT NULL,
  `x` float NOT NULL,
  `y` float NOT NULL,
  `z` float NOT NULL,
  UNIQUE KEY `steamid` (`steamid`,`map`,`id`,`class`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `jump_courses`
--

CREATE TABLE IF NOT EXISTS `jump_courses` (
  `id` int(11) NOT NULL auto_increment,
  `map` varchar(128) NOT NULL,
  `name` varchar(128) NOT NULL,
  `start_x` float NOT NULL,
  `start_y` float NOT NULL,
  `start_z` float NOT NULL,
  `end_x` float NOT NULL,
  `end_y` float NOT NULL,
  `end_z` float NOT NULL,
  PRIMARY KEY  (`id`)
) ENGINE=InnoDB  DEFAULT CHARSET=latin1 AUTO_INCREMENT=193 ;

-- --------------------------------------------------------

--
-- Table structure for table `jump_maps`
--

CREATE TABLE IF NOT EXISTS `jump_maps` (
  `map` varchar(128) NOT NULL,
  `enabled` tinyint(1) NOT NULL default '1',
  PRIMARY KEY  (`map`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `jump_times`
--

CREATE TABLE IF NOT EXISTS `jump_times` (
  `id` int(11) NOT NULL auto_increment,
  `course_id` int(11) NOT NULL,
  `name` varchar(128) NOT NULL,
  `steamid` varchar(64) NOT NULL,
  `class` int(11) NOT NULL,
  `ammo` int(11) NOT NULL,
  `hardcore` int(11) NOT NULL,
  `time` int(11) NOT NULL,
  `timestamp` timestamp NOT NULL default '0000-00-00 00:00:00' on update CURRENT_TIMESTAMP,
  PRIMARY KEY  (`id`)
) ENGINE=InnoDB  DEFAULT CHARSET=latin1 AUTO_INCREMENT=42120 ;

-- --------------------------------------------------------
